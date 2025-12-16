#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <sys/inotify.h>

int main(int argc, char** argv) {
  if (argc < 4) return 1;

  signal(SIGCHLD, SIG_IGN);

  char* link = argv[0];
  char* dir = argv[1];
  char* script = argv[2];
  int mode = atoi(argv[3]);

  int fd = inotify_init();
  if (fd < 0) return 1;

  int wd = inotify_add_watch(fd, dir, IN_CREATE | IN_MOVED_TO | IN_DELETE_SELF);
  if (wd < 0) return 1;

  char buf[1024];

  for (;;) {
    int len = read(fd, buf, sizeof(buf));
    if (len <= 0) return 1;

    int i = 0;
    while (i < len) {
      struct inotify_event* ev = (void*)(buf + i);

      if (ev->mask & IN_DELETE_SELF) {
        unlink(link);
        return 0;
      }

      if ((mode == 0 && (ev->mask & IN_CREATE) && (ev->mask & IN_ISDIR)) ||
        (mode == 1 && (ev->mask & IN_MOVED_TO) && (ev->mask & IN_ISDIR))) {
        if (fork() == 0) {
          execl("/system/bin/sh", "sh", script, dir, ev->name, (char*)NULL);
          _exit(0);
        }
      }

      i += sizeof(struct inotify_event) + ev->len;
    }
  }

  return 0;
}
