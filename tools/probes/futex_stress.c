/* futex_stress.c - SeaBSD linuxolator futex stress probe.
 *
 * Copyright (c) 2026, SeaBSD Project
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * A self-contained Linux ELF binary that exercises the futex paths the
 * linuxolator must translate for any threaded application: wait/wake with
 * the private flag, relative and absolute timeouts on both timebases,
 * bitset wakeups, requeue, futex_waitv and a correctness loop under heavy
 * contention. CI builds it as a static binary on an Ubuntu runner (where a
 * Linux compiler is available) and executes it twice: on real Linux as a
 * sanity check of the probe itself, and on FreeBSD through the linuxolator
 * as the compatibility signal (see tools/linux-matrix.sh, docs/futex.md).
 *
 * Usage:
 *   futex_stress [test ...]     run the named tests (default: all)
 *   futex_stress --list         list test names
 *
 * Exit codes (consumed by tools/linux-matrix.sh):
 *   0    all executed tests passed
 *   1    at least one executed test failed
 *   77   every selected test reported "not implemented" on this host
 *   124  watchdog fired: deadlock or extreme slowness suspected
 *   3    usage error
 */

#define _GNU_SOURCE
#include <errno.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <signal.h>
#include <sys/syscall.h>
#include <linux/futex.h>
#include <linux/types.h>

/* futex_waitv postdates some toolchain headers; provide the definitions so
 * the probe still builds against older ones. FUTEX_WAITV_MAX appears in the
 * kernel header exactly when it also declares struct futex_waitv, so it is
 * the reliable guard for the struct definition. */
#ifndef FUTEX_WAITV
#define FUTEX_WAITV 15
#endif
#ifndef FUTEX_WAITV_MAX
struct futex_waitv {
        __u64 val;
        __u64 uaddr;
        __u32 flags;
        __u32 __reserved;
};
#endif
#ifndef FUTEX_32
#define FUTEX_32 2
#endif
#ifndef __NR_futex_waitv
#define __NR_futex_waitv 449
#endif
#ifndef FUTEX_BITSET_MATCH_ANY
#define FUTEX_BITSET_MATCH_ANY 0xffffffffU
#endif

#define WW_NTHREADS     4
#define RQ_NTHREADS     4
#define CT_NTHREADS     8
#define CT_ITERATIONS   1000
#define HANDSHAKE_SECS  2.0
#define TEST_DEADLINE   10.0
#define WAIT_STEP_MS    250
#define WATCHDOG_SECS   120

/* --------------------------------------------------------------- helpers */

static long futex_call(uint32_t *uaddr, int op, uint32_t val,
                       const struct timespec *ts, uint32_t *uaddr2,
                       uint32_t val3)
{
        return syscall(SYS_futex, uaddr, op, val, ts, uaddr2, val3);
}

/* Detail message of the first failure inside the currently running test. */
static char g_err[256];

static void failf(const char *fmt, ...)
{
        va_list ap;

        va_start(ap, fmt);
        vsnprintf(g_err, sizeof(g_err), fmt, ap);
        va_end(ap);
}

static double now_mono(void)
{
        struct timespec ts;

        clock_gettime(CLOCK_MONOTONIC, &ts);
        return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static void ts_add_ms(struct timespec *ts, long ms)
{
        ts->tv_sec += ms / 1000;
        ts->tv_nsec += (ms % 1000) * 1000000L;
        if (ts->tv_nsec >= 1000000000L) {
                ts->tv_sec += 1;
                ts->tv_nsec -= 1000000000L;
        }
}

static void watchdog_handler(int sig)
{
        static const char msg[] =
            "futex_stress: WATCHDOG fired - deadlock or extreme slowness\n";
        ssize_t n;

        (void)sig;
        n = write(STDERR_FILENO, msg, sizeof(msg) - 1);
        (void)n;
        _exit(124);
}

/* Wait until *cell reaches `want` or the budget expires (main thread only). */
static int wait_atomic_ge(_Atomic int *cell, int want, double budget)
{
        double t0 = now_mono();

        while (now_mono() - t0 < budget) {
                if (__atomic_load_n(cell, __ATOMIC_ACQUIRE) >= want)
                        return 0;
                usleep(1000);
        }
        return -1;
}

/* ------------------------------------------------------- shared test state */

static uint32_t g_f1;           /* primary futex word (0 = waiters sleep)   */
static uint32_t g_f2;           /* requeue target futex word                */
static _Atomic int g_asleep;    /* waiters that entered the sleep loop      */
static _Atomic int g_woken;     /* waiters that report a successful wake    */
static _Atomic int g_terr;      /* thread-side kernel errors                */
static _Atomic int g_stuck;     /* waiters that hit the deadline un-woken   */
static _Atomic int g_done;      /* waiters that finished (any way at all)   */
static _Atomic long g_counter;  /* contention critical-section counter      */
static uint32_t g_lock;         /* contention futex-based lock word         */
static double g_deadline;       /* per-test wall-clock deadline (mono secs) */

typedef int (*test_fn)(void);

struct test {
        const char *name;
        test_fn fn;
};

/* Wake up to `want` sleepers, retrying until the deadline. This keeps the
 * wake-count assertions honest even when a waiter is between time-sliced
 * waits, and it cannot hang. */
static long wake_retry(uint32_t *uaddr, int op, int want, uint32_t bitset)
{
        long total = 0;

        while (total < want && now_mono() < g_deadline) {
                long r = futex_call(uaddr, op, (uint32_t)(want - total), NULL,
                    NULL, bitset);

                if (r > 0)
                        total += r;
                else if (r == -1 && errno == EINVAL)
                        break;
                usleep(2000);
        }
        return total;
}

/* ----------------------------------------------------------- waiter bodies */

/* Sleep on g_f1 until its value becomes non-zero (plain FUTEX_WAIT).
 * All waiter loops use time-sliced waits plus a test deadline: a kernel
 * that loses wakeups produces a FAIL report, never a probe-wide hang. */
static void *waiter_plain(void *arg)
{
        struct timespec ts = { .tv_sec = 0, .tv_nsec = WAIT_STEP_MS * 1000000L };

        (void)arg;
        __atomic_add_fetch(&g_asleep, 1, __ATOMIC_SEQ_CST);
        for (;;) {
                if (__atomic_load_n(&g_f1, __ATOMIC_ACQUIRE) != 0)
                        break;
                if (now_mono() > g_deadline) {
                        __atomic_add_fetch(&g_stuck, 1, __ATOMIC_SEQ_CST);
                        break;
                }
                if (futex_call(&g_f1, FUTEX_WAIT_PRIVATE, 0, &ts, NULL,
                    0) == -1) {
                        if (errno == EAGAIN || errno == EINTR ||
                            errno == ETIMEDOUT)
                                continue;
                        __atomic_add_fetch(&g_terr, 1, __ATOMIC_SEQ_CST);
                        break;
                }
                __atomic_add_fetch(&g_woken, 1, __ATOMIC_SEQ_CST);
                break;
        }
        __atomic_add_fetch(&g_done, 1, __ATOMIC_SEQ_CST);
        return NULL;
}

/* Same, but with FUTEX_WAIT_BITSET restricted to bit 0x2. NOTE: WAIT_BITSET
 * interprets its timeout as ABSOLUTE (unlike the relative FUTEX_WAIT), so
 * each slice computes a fresh absolute deadline. */
static void *waiter_bitset(void *arg)
{
        (void)arg;
        __atomic_add_fetch(&g_asleep, 1, __ATOMIC_SEQ_CST);
        for (;;) {
                struct timespec dl;

                if (__atomic_load_n(&g_f1, __ATOMIC_ACQUIRE) != 0)
                        break;
                if (now_mono() > g_deadline) {
                        __atomic_add_fetch(&g_stuck, 1, __ATOMIC_SEQ_CST);
                        break;
                }
                clock_gettime(CLOCK_MONOTONIC, &dl);
                ts_add_ms(&dl, WAIT_STEP_MS);
                if (futex_call(&g_f1, FUTEX_WAIT_BITSET_PRIVATE, 0, &dl, NULL,
                    0x2) == -1) {
                        if (errno == EAGAIN || errno == EINTR ||
                            errno == ETIMEDOUT)
                                continue;
                        __atomic_add_fetch(&g_terr, 1, __ATOMIC_SEQ_CST);
                        break;
                }
                __atomic_add_fetch(&g_woken, 1, __ATOMIC_SEQ_CST);
                break;
        }
        __atomic_add_fetch(&g_done, 1, __ATOMIC_SEQ_CST);
        return NULL;
}

/* Waiter that survives being requeued from g_f1 to g_f2 mid-sleep: the loop
 * re-checks both words and only exits when one of them is non-zero. */
static void *waiter_requeue(void *arg)
{
        struct timespec ts = { .tv_sec = 0, .tv_nsec = WAIT_STEP_MS * 1000000L };

        (void)arg;
        __atomic_add_fetch(&g_asleep, 1, __ATOMIC_SEQ_CST);
        for (;;) {
                if (__atomic_load_n(&g_f1, __ATOMIC_ACQUIRE) != 0 ||
                    __atomic_load_n(&g_f2, __ATOMIC_ACQUIRE) != 0)
                        break;
                if (now_mono() > g_deadline) {
                        __atomic_add_fetch(&g_stuck, 1, __ATOMIC_SEQ_CST);
                        break;
                }
                if (futex_call(&g_f1, FUTEX_WAIT_PRIVATE, 0, &ts, NULL,
                    0) == -1) {
                        if (errno == EAGAIN || errno == EINTR ||
                            errno == ETIMEDOUT)
                                continue;
                        __atomic_add_fetch(&g_terr, 1, __ATOMIC_SEQ_CST);
                        break;
                }
                /* Woken directly before the requeue, or woken on g_f2 after
                 * being requeued; both cases fall through to the re-check. */
        }
        __atomic_add_fetch(&g_done, 1, __ATOMIC_SEQ_CST);
        return NULL;
}

/* ------------------------------------------------------------------ tests */

static int t_waitwake(void)
{
        pthread_t th[WW_NTHREADS];
        long total;
        int i, err = 0;

        __atomic_store_n(&g_f1, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_asleep, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_woken, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_terr, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_stuck, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_done, 0, __ATOMIC_SEQ_CST);
        g_deadline = now_mono() + TEST_DEADLINE;

        for (i = 0; i < WW_NTHREADS; i++)
                if (pthread_create(&th[i], NULL, waiter_plain, NULL) != 0) {
                        failf("pthread_create failed: %s", strerror(errno));
                        return 1;
                }

        if (wait_atomic_ge(&g_asleep, WW_NTHREADS, HANDSHAKE_SECS) != 0) {
                failf("only %d/%d waiters went to sleep", g_asleep,
                    WW_NTHREADS);
                err = 1;
        }
        usleep(20000);
        __atomic_store_n(&g_f1, 1, __ATOMIC_SEQ_CST);
        total = wake_retry(&g_f1, FUTEX_WAKE_PRIVATE, WW_NTHREADS,
            FUTEX_BITSET_MATCH_ANY);
        for (i = 0; i < WW_NTHREADS; i++)
                pthread_join(th[i], NULL);

        if (total != WW_NTHREADS) {
                failf("FUTEX_WAKE woke %ld threads, expected %d", total,
                    WW_NTHREADS);
                err = 1;
        }
        if (__atomic_load_n(&g_done, __ATOMIC_SEQ_CST) != WW_NTHREADS) {
                failf("only %d/%d waiters finished", g_done, WW_NTHREADS);
                err = 1;
        }
        if (__atomic_load_n(&g_stuck, __ATOMIC_SEQ_CST) != 0) {
                failf("%d waiters hit the deadline without a wakeup", g_stuck);
                err = 1;
        }
        if (__atomic_load_n(&g_terr, __ATOMIC_SEQ_CST) != 0) {
                failf("%d waiter threads reported kernel errors", g_terr);
                err = 1;
        }
        return err;
}

/* Shared validation for timed waits: the call must fail with ETIMEDOUT and
 * the measured wall time must respect the requested window. */
static int expect_timeout(const char *what, long r, double dt,
                          double lo_ms, double hi_ms)
{
        if (r != -1) {
                failf("%s: returned %ld instead of timing out", what, r);
                return 1;
        }
        if (errno != ETIMEDOUT) {
                failf("%s: errno=%s, expected ETIMEDOUT", what,
                    strerror(errno));
                return 1;
        }
        if (dt * 1000.0 < lo_ms) {
                failf("%s: timed out after %.2f ms (below %.2f ms; timeout "
                    "rounding bug?)", what, dt * 1000.0, lo_ms);
                return 1;
        }
        if (dt * 1000.0 > hi_ms) {
                failf("%s: took %.2f ms (above %.2f ms ceiling)", what,
                    dt * 1000.0, hi_ms);
                return 1;
        }
        return 0;
}

static int t_timed_rel(void)
{
        struct timespec ts;
        double t0, dt;
        long r;
        int bad;

        __atomic_store_n(&g_f1, 0, __ATOMIC_SEQ_CST);

        /* 50 ms relative timeout against CLOCK_MONOTONIC (FUTEX_WAIT
         * semantics). */
        ts.tv_sec = 0;
        ts.tv_nsec = 50 * 1000 * 1000L;
        t0 = now_mono();
        r = futex_call(&g_f1, FUTEX_WAIT_PRIVATE, 0, &ts, NULL, 0);
        dt = now_mono() - t0;
        bad = expect_timeout("relative 50ms timedwait", r, dt, 40.0, 2000.0);

        /* 1 ms relative timeout: catches implementations that round the
         * timeout down to zero ticks and return immediately with success. */
        ts.tv_sec = 0;
        ts.tv_nsec = 1000000L;
        t0 = now_mono();
        r = futex_call(&g_f1, FUTEX_WAIT_PRIVATE, 0, &ts, NULL, 0);
        dt = now_mono() - t0;
        if (!bad)
                bad = expect_timeout("relative 1ms timedwait", r, dt,
                    0.0, 1000.0);
        return bad;
}

static int t_timed_abs_mono(void)
{
        struct timespec dl;
        double t0, dt;
        long r;

        __atomic_store_n(&g_f1, 0, __ATOMIC_SEQ_CST);
        clock_gettime(CLOCK_MONOTONIC, &dl);
        ts_add_ms(&dl, 50);
        t0 = now_mono();
        r = futex_call(&g_f1, FUTEX_WAIT_BITSET_PRIVATE, 0, &dl, NULL,
            FUTEX_BITSET_MATCH_ANY);
        dt = now_mono() - t0;
        return expect_timeout("absolute monotonic timedwait", r, dt,
            40.0, 2000.0);
}

static int t_timed_abs_rt(void)
{
        struct timespec dl;
        double t0, dt;
        long r;

        __atomic_store_n(&g_f1, 0, __ATOMIC_SEQ_CST);
        clock_gettime(CLOCK_REALTIME, &dl);
        ts_add_ms(&dl, 50);
        t0 = now_mono();
        r = futex_call(&g_f1, FUTEX_WAIT_BITSET_PRIVATE | FUTEX_CLOCK_REALTIME,
            0, &dl, NULL, FUTEX_BITSET_MATCH_ANY);
        dt = now_mono() - t0;
        return expect_timeout("absolute realtime timedwait", r, dt,
            40.0, 2000.0);
}

static int t_bitset(void)
{
        pthread_t th[WW_NTHREADS];
        long r, total;
        int i, err = 0;

        __atomic_store_n(&g_f1, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_asleep, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_woken, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_terr, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_stuck, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_done, 0, __ATOMIC_SEQ_CST);
        g_deadline = now_mono() + TEST_DEADLINE;

        for (i = 0; i < WW_NTHREADS; i++)
                if (pthread_create(&th[i], NULL, waiter_bitset, NULL) != 0) {
                        failf("pthread_create failed: %s", strerror(errno));
                        return 1;
                }

        if (wait_atomic_ge(&g_asleep, WW_NTHREADS, HANDSHAKE_SECS) != 0) {
                failf("only %d/%d waiters went to sleep", g_asleep,
                    WW_NTHREADS);
                err = 1;
        }
        usleep(20000);
        __atomic_store_n(&g_f1, 1, __ATOMIC_SEQ_CST);

        /* Mismatched bit must wake nobody; WAKE_BITSET ignores the value. */
        r = futex_call(&g_f1, FUTEX_WAKE_BITSET_PRIVATE, WW_NTHREADS, NULL,
            NULL, 0x4);
        if (r != 0) {
                failf("WAKE_BITSET with a mismatched bit woke %ld waiters", r);
                err = 1;
        }

        total = wake_retry(&g_f1, FUTEX_WAKE_BITSET_PRIVATE, WW_NTHREADS,
            0x2);
        for (i = 0; i < WW_NTHREADS; i++)
                pthread_join(th[i], NULL);

        if (total != WW_NTHREADS) {
                failf("WAKE_BITSET with matching bit woke %ld, expected %d",
                    total, WW_NTHREADS);
                err = 1;
        }
        if (__atomic_load_n(&g_done, __ATOMIC_SEQ_CST) != WW_NTHREADS) {
                failf("only %d/%d waiters finished", g_done, WW_NTHREADS);
                err = 1;
        }
        if (__atomic_load_n(&g_stuck, __ATOMIC_SEQ_CST) != 0) {
                failf("%d waiters hit the deadline without a wakeup", g_stuck);
                err = 1;
        }
        if (__atomic_load_n(&g_terr, __ATOMIC_SEQ_CST) != 0) {
                failf("%d waiter threads reported kernel errors", g_terr);
                err = 1;
        }
        return err;
}

/* Requeue: wake one waiter, move the rest from g_f1 to g_f2, wake them
 * there. `use_cmp` selects the glibc-realistic FUTEX_CMP_REQUEUE variant
 * (val3 = expected value) versus plain FUTEX_REQUEUE. Waiters use
 * time-sliced waits and a deadline, and the test rescues both queues
 * before joining: any kernel regression surfaces as FAIL, never as a
 * probe-wide hang. */
static int run_requeue(int use_cmp)
{
        pthread_t th[RQ_NTHREADS];
        long r, total = 0;
        int i, err = 0;
        int op = use_cmp ? FUTEX_CMP_REQUEUE_PRIVATE : FUTEX_REQUEUE_PRIVATE;

        __atomic_store_n(&g_f1, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_f2, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_asleep, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_woken, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_terr, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_stuck, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_done, 0, __ATOMIC_SEQ_CST);
        g_deadline = now_mono() + TEST_DEADLINE;

        for (i = 0; i < RQ_NTHREADS; i++)
                if (pthread_create(&th[i], NULL, waiter_requeue, NULL) != 0) {
                        failf("pthread_create failed: %s", strerror(errno));
                        return 1;
                }

        if (wait_atomic_ge(&g_asleep, RQ_NTHREADS, HANDSHAKE_SECS) != 0) {
                failf("only %d/%d waiters went to sleep", g_asleep,
                    RQ_NTHREADS);
                err = 1;
        }
        usleep(20000);

        __atomic_store_n(&g_f1, 1, __ATOMIC_SEQ_CST);
        /* nr_requeue travels in the timeout argument slot. */
        r = futex_call(&g_f1, op, 1,
            (const struct timespec *)(uintptr_t)(RQ_NTHREADS - 1), &g_f2,
            use_cmp ? 1u : 0u);
        if (r != RQ_NTHREADS) {
                if (r == -1)
                        failf("%s failed: %s (errno=%d)",
                            use_cmp ? "FUTEX_CMP_REQUEUE" : "FUTEX_REQUEUE",
                            strerror(errno), errno);
                else
                        failf("%s moved %ld, expected %d (1 wake + %d requeued)",
                            use_cmp ? "FUTEX_CMP_REQUEUE" : "FUTEX_REQUEUE", r,
                            RQ_NTHREADS, RQ_NTHREADS - 1);
                err = 1;
        }

        __atomic_store_n(&g_f2, 1, __ATOMIC_SEQ_CST);
        total = wake_retry(&g_f2, FUTEX_WAKE_PRIVATE, RQ_NTHREADS,
            FUTEX_BITSET_MATCH_ANY);
        if (!err && total != RQ_NTHREADS - 1) {
                failf("FUTEX_WAKE on requeue target woke %ld, expected %d",
                    total, RQ_NTHREADS - 1);
                err = 1;
        }

        /* Rescue: whatever happened above, nobody gets to hang. Waking both
         * words lets requeued or stranded waiters exit via their predicate. */
        futex_call(&g_f1, FUTEX_WAKE_PRIVATE, RQ_NTHREADS, NULL, NULL, 0);
        futex_call(&g_f2, FUTEX_WAKE_PRIVATE, RQ_NTHREADS, NULL, NULL, 0);

        for (i = 0; i < RQ_NTHREADS; i++)
                pthread_join(th[i], NULL);

        if (__atomic_load_n(&g_done, __ATOMIC_SEQ_CST) != RQ_NTHREADS) {
                failf("only %d/%d waiters finished", g_done, RQ_NTHREADS);
                err = 1;
        }
        if (__atomic_load_n(&g_stuck, __ATOMIC_SEQ_CST) != 0) {
                failf("%d waiters hit the deadline without a wakeup "
                    "(requeued waiters lost?)", g_stuck);
                err = 1;
        }
        if (__atomic_load_n(&g_terr, __ATOMIC_SEQ_CST) != 0) {
                failf("%d waiter threads reported kernel errors", g_terr);
                err = 1;
        }
        return err;
}

static int t_requeue(void)
{
        return run_requeue(1);
}

static int t_requeue_nc(void)
{
        return run_requeue(0);
}

/* Wake a futex_waitv sleeper through its second list entry. */
static void *waitv_waker(void *arg)
{
        uint32_t *fb = arg;

        usleep(50000);
        __atomic_store_n(fb, 1, __ATOMIC_SEQ_CST);
        futex_call(fb, FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0);
        return NULL;
}

static int t_waitv(void)
{
        struct futex_waitv wv[2];
        uint32_t fa = 0, fb = 0;
        pthread_t th;
        long r;

        memset(&wv, 0, sizeof(wv));
        wv[0].val = 0;
        wv[0].uaddr = (uintptr_t)&fa;
        wv[0].flags = FUTEX_32 | FUTEX_PRIVATE_FLAG;
        wv[1].val = 0;
        wv[1].uaddr = (uintptr_t)&fb;
        wv[1].flags = FUTEX_32 | FUTEX_PRIVATE_FLAG;

        if (pthread_create(&th, NULL, waitv_waker, &fb) != 0) {
                failf("pthread_create failed: %s", strerror(errno));
                return 1;
        }

        r = syscall(__NR_futex_waitv, wv, 2, 0, NULL, 0);
        if (r == -1 && errno == ENOSYS) {
                pthread_join(th, NULL);
                failf("futex_waitv not implemented on this host");
                return 77;
        }
        if (r == -1) {
                failf("futex_waitv failed: %s", strerror(errno));
                pthread_join(th, NULL);
                return 1;
        }
        if (r != 1) {
                failf("futex_waitv returned index %ld, expected 1 (futex fb)",
                    r);
                pthread_join(th, NULL);
                return 1;
        }
        pthread_join(th, NULL);
        return 0;
}

static void *contender(void *arg)
{
        struct timespec ts = { .tv_sec = 0, .tv_nsec = WAIT_STEP_MS * 1000000L };
        int i;

        (void)arg;
        for (i = 0; i < CT_ITERATIONS; i++) {
                for (;;) {
                        uint32_t expected = 0;

                        if (__atomic_compare_exchange_n(&g_lock, &expected, 1,
                            0, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED))
                                break;
                        if (futex_call(&g_lock, FUTEX_WAIT_PRIVATE, 1, &ts,
                            NULL, 0) == -1 && errno != EAGAIN &&
                            errno != EINTR && errno != ETIMEDOUT) {
                                __atomic_add_fetch(&g_terr, 1,
                                    __ATOMIC_SEQ_CST);
                                return NULL;
                        }
                }
                __atomic_add_fetch(&g_counter, 1, __ATOMIC_SEQ_CST);
                __atomic_store_n(&g_lock, 0, __ATOMIC_RELEASE);
                futex_call(&g_lock, FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0);
        }
        return NULL;
}

static int t_contention(void)
{
        pthread_t th[CT_NTHREADS];
        long expect_total = (long)CT_NTHREADS * CT_ITERATIONS;
        int i, err = 0;

        g_lock = 0;
        __atomic_store_n(&g_counter, 0, __ATOMIC_SEQ_CST);
        __atomic_store_n(&g_terr, 0, __ATOMIC_SEQ_CST);

        for (i = 0; i < CT_NTHREADS; i++)
                if (pthread_create(&th[i], NULL, contender, NULL) != 0) {
                        failf("pthread_create failed: %s", strerror(errno));
                        return 1;
                }
        for (i = 0; i < CT_NTHREADS; i++)
                pthread_join(th[i], NULL);

        if (__atomic_load_n(&g_terr, __ATOMIC_SEQ_CST) != 0) {
                failf("%d contender threads reported kernel errors", g_terr);
                err = 1;
        }
        if (!err && __atomic_load_n(&g_counter, __ATOMIC_SEQ_CST) !=
            expect_total) {
                failf("counter is %ld, expected %ld (futex atomicity "
                    "violated)", g_counter, expect_total);
                err = 1;
        }
        return err;
}

/* ---------------------------------------------------------------- registry */

static int t_waitwake(void);
static int t_timed_rel(void);
static int t_timed_abs_mono(void);
static int t_timed_abs_rt(void);
static int t_bitset(void);
static int t_requeue(void);
static int t_requeue_nc(void);
static int t_waitv(void);
static int t_contention(void);

static const struct test tests[] = {
        { "waitwake",   t_waitwake },
        { "timed_rel",  t_timed_rel },
        { "timed_abs_mono", t_timed_abs_mono },
        { "timed_abs_rt",       t_timed_abs_rt },
        { "bitset",             t_bitset },
        { "requeue",            t_requeue },
        { "requeue_nc",         t_requeue_nc },
        { "waitv",              t_waitv },
        { "contention",         t_contention },
};

/* ------------------------------------------------------------------- main */

int main(int argc, char **argv)
{
        size_t ntests = sizeof(tests) / sizeof(tests[0]);
        int npass = 0, nfail = 0, nskip = 0, rc, rc_exit;
        size_t t;
        int i, j;

        signal(SIGALRM, watchdog_handler);
        alarm(WATCHDOG_SECS);

        if (argc > 1 && strcmp(argv[1], "--list") == 0) {
                for (t = 0; t < ntests; t++)
                        printf("%s\n", tests[t].name);
                return 0;
        }

        for (i = 1; i < argc; i++) {
                int found = 0;

                for (t = 0; t < ntests; t++)
                        if (strcmp(argv[i], tests[t].name) == 0)
                                found = 1;
                if (!found) {
                        fprintf(stderr,
                            "futex_stress: unknown test: %s\n", argv[i]);
                        fprintf(stderr, "usage: futex_stress [--list] "
                            "[test ...]\n");
                        return 3;
                }
        }

        for (t = 0; t < ntests; t++) {
                int selected = (argc <= 1);

                for (j = 1; j < argc; j++)
                        if (strcmp(argv[j], tests[t].name) == 0)
                                selected = 1;
                if (!selected)
                        continue;

                g_err[0] = '\0';
                /* Per-test wall-clock deadline: waiter loops stop waiting and
                 * report "stuck" instead of hanging the whole probe. */
                g_deadline = now_mono() + TEST_DEADLINE;
                /* Progress markers survive a hang: whoever reads the captured
                 * output sees exactly which test was running when it stopped. */
                printf("RUN %s\n", tests[t].name);
                fflush(stdout);
                rc = tests[t].fn();
                if (rc == 0) {
                        npass++;
                        printf("PASS %s\n", tests[t].name);
                } else if (rc == 77) {
                        nskip++;
                        printf("SKIP %s (%s)\n", tests[t].name, g_err);
                } else {
                        nfail++;
                        printf("FAIL %s (%s)\n", tests[t].name,
                            g_err[0] != '\0' ? g_err : "no detail");
                }
                fflush(stdout);
        }

        printf("SUMMARY: pass=%d fail=%d skip=%d\n", npass, nfail, nskip);
        if (nfail > 0)
                rc_exit = 1;
        else if (npass == 0 && nskip > 0)
                rc_exit = 77;
        else
                rc_exit = 0;
        return rc_exit;
}
