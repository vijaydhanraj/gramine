#define _GNU_SOURCE
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

static void wait_for_failing_child(int pid) {
    int status;

    pid_t child_pid = waitpid(pid, &status, 0);
    if (child_pid < 0) {
        err(1, "waitpid");
    } else if (child_pid != pid) {
        errx(1, "wrong child pid %d", child_pid);
    }

    if (!WIFSIGNALED(status)) {
        errx(1, "child %d not killed (%d)", child_pid, status);
    }
    if (WTERMSIG(status) != SIGSEGV) {
         errx(1, "child died in an unknown manner: %d", status);
    }
}

static int test_segfault_on_write_to_rx_page(void) {
    pid_t child_pid = fork();
    if (child_pid == 0) {
        int* ptr = (int*)test_segfault_on_write_to_rx_page;

        /* *ptr = 0; */
        __asm__ volatile("movl $0, (%0)\n" : "=r"(ptr) : : "memory");

        exit(1); /* child must not survive the write to RX page above */
    }

    return child_pid;
}

static int test_segfault_on_exec_to_rw_page(void) {
    pid_t child_pid = fork();
    if (child_pid == 0) {
        int on_stack_var = 5;
        int* rw_addr = &on_stack_var;

        __asm__ volatile("jmp *(%0)" : : "r" (rw_addr));

        exit(1); /* child must not survive exec attempt of RW page above */
    }

    return child_pid;
}

static int test_segfault_on_write_to_ro_page(void) {
    pid_t child_pid = fork();
    if (child_pid == 0) {
        char* str = (char*)"Hello World!"; /* suppress const warning by casting to char* */

        /* str[0] = 'h'; */
        __asm__ volatile("movb $104, (%0)\n" : "=r"(str) : : "memory");

        exit(1); /* child must not survive the write to RO page above */
    }

    return child_pid;
}

int main(void) {
    pid_t child_pid = test_segfault_on_write_to_rx_page();
    if (child_pid < 0) {
        err(1, "fork");
    }
    wait_for_failing_child(child_pid);

    child_pid = test_segfault_on_exec_to_rw_page();
    if (child_pid < 0) {
        err(1, "fork");
    }
    wait_for_failing_child(child_pid);

    child_pid = test_segfault_on_write_to_ro_page();
    if (child_pid < 0) {
        err(1, "fork");
    }
    wait_for_failing_child(child_pid);

    puts("TEST OK");
    return 0;
}
