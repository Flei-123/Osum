#include <unistd.h>
#include <stdio.h>
int main(int argc, char **argv, char **envp){
  printf("argc=%d\n", argc);
  for(int i=0;i<argc;i++) printf("argv[%d]=[%s]\n", i, argv[i]?argv[i]:"(nil)");
  for(int i=0;envp && envp[i] && i<5;i++) printf("env[%d]=[%s]\n", i, envp[i]);
  fflush(stdout);
  return 0;
}
