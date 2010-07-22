To test Cloudsource as a non-root user: 

1) cd test; ./setup_env
2) vim set_env # add SVN parameters.
3) . set_env  # load environment params. 
4) ../bin/deploy.sh --no-root # installs bin/ and roles/ into test/
5) use bin/role.sh to test new Cloudsource commands.
