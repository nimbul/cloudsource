#!/bin/bash

# test that rbconfig has CXX defined - eventmachine install will fail if it doesn't
if ! ruby -rrbconfig -e 'exit RbConfig::MAKEFILE_CONFIG["CXX"].nil? ? 1 : 0'; then
	updatedb -f fuse -e /mnt # need to updatedb first so we can locate rbconfig.rb
	echo "RubyConfig missing CXX definition - setting it to 'g++'"
	sed -r -e "/CONFIG\[.CC.\]/a \
        CONFIG['CXX'] = 'g++'" -i $(locate rbconfig.rb | tail -n 1)
fi

echo "Installing Emissary"
install_list="emissary"

for lib in fastthread escape inifile sys-cpu daemons bert servolux uuid work_queue amqp eventmachine; do 
  if [ $(gem list --local $lib | grep $lib -c) -le 0 ]; then
    echo "Adding missing required library '${lib}' to list of gems to install"
    install_list="$lib ${install_list}"
  fi
done

if [ $(echo $install_list | egrep -ic '(eventmachine|sys-cpu|bert|fastthread)') -ge 1 ]; then
  need_gcc=1
else
  need_gcc=0
fi

if [ $need_gcc -eq 1 ]; then
  echo "Need GCC to install some required gems - performing yum install now.."
  yum install -y libstdc* gcc* --quiet
fi

if [ "$(ruby -e 'puts RUBY_VERSION == "1.8.7" ? "ok" : "upgrade"')" != "ok" ]; then
  echo "Ruby VERSION Test: got '$(ruby -e 'puts RUBY_VERSION')' - expected: '1.8.7'... Installing Ruby-1.8.7..."
  yum install readline-devel -y

  wget http://nytd-downloads.s3.amazonaws.com/ruby-1.8.7.tar.gz
  tar xvzf ruby-1.8.7.tar.gz
  cd ruby-*
  ./configure --prefix /usr && make && make install
  gem update --system
  cd ..
  rm -rf ruby-*
fi
  
gem install --remote ${install_list} --no-ri --no-rdoc

emissary-setup /etc
emissary start -d