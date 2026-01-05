#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <sys/inotify.h>

int main(int argc, char** argv) {
  if (argc < 4) return 1;

  struct sigaction sa = {
    .sa_handler = SIG_IGN,
    .sa_flags = SA_NOCLDWAIT
  };
  sigemptyset(&sa.sa_mask);
  sigaction(SIGCHLD, &sa, NULL);

  char* script = argv[1];
  char* dir = argv[2];
  char* event = argv[3];

  int fd = inotify_init();
  if (fd < 0) return 1;

  int wd = inotify_add_watch(
    fd, dir, IN_CREATE | IN_MOVED_TO | IN_DELETE_SELF
  );
  if (wd < 0) return 1;

  char buf[4096];

  for (;;) {
    int bt = read(fd, buf, sizeof(buf));
    if (bt <= 0) return 1;

    int i = 0;
    while (i < bt) {
      struct inotify_event* ev = (void*)(buf + i);

      int match = (event[0] == 'n' && (ev->mask & IN_CREATE)) ||
        (event[0] == 'm' && (ev->mask & IN_MOVED_TO));

      if (match && (ev->mask & IN_ISDIR)) {
        if (fork() == 0) {
          execl("/system/bin/sh", "sh", script, event, dir, ev->name, (char*)NULL);
          _exit(1);
        }
      }

      if (ev->mask & IN_DELETE_SELF) return 0;

      i += sizeof(struct inotify_event) + ev->len;
    }
  }

  return 0;
}
