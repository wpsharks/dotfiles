#!/usr/bin/env bash

# ----------------------------------------------------------------------------------------------------------------------

# Strict mode.

set -o nounset;
set -o errexit;
set -o errtrace;
set -o pipefail;

# ----------------------------------------------------------------------------------------------------------------------

# Shell options.

shopt -s dotglob;
shopt -s globstar;
shopt -s nullglob;
shopt -s failglob;

# ----------------------------------------------------------------------------------------------------------------------

# Stack trace on error; via `trap`.

function stack-trace() {
  set +o xtrace; # Disable.

  local last_command_status_code=$?;
  local exit_status_code="${1:-1}";

  echo '----------------------------------------------------------------------';
  echo 'Referencing: '"${BASH_SOURCE[1]}"':'"${BASH_LINENO[0]}";
  echo '`'"${BASH_COMMAND}"'` exited with status `'"${last_command_status_code}"'`.';

  if [[ ${#FUNCNAME[@]} -gt 2 ]]; then
    echo 'Stack Trace:';
    for ((_i=1; _i < ${#FUNCNAME[@]}-1; _i++)); do
      echo " ${_i}: ${BASH_SOURCE[${_i}+1]}:${BASH_LINENO[${_i}]} ${FUNCNAME[${_i}]}(...)";
    done;
  fi;
  exit "${exit_status_code}";
};
trap stack-trace ERR; # Trap errors & print a stack trace.

# ----------------------------------------------------------------------------------------------------------------------

# For debugging purposes.
# set -o xtrace; # Print each command that is run.

# ----------------------------------------------------------------------------------------------------------------------

# Define local variables.

build_dir="${TRAVIS_BUILD_DIR}";
php_version="${TRAVIS_PHP_VERSION}";
php_exact_version="$(php -r 'echo PHP_VERSION;')";

# ----------------------------------------------------------------------------------------------------------------------

# Create dirs; including a persistent cache directory.
# See: <https://docs.travis-ci.com/user/caching/>

if [[ ! -d ~/bin ]]; then
  mkdir ~/bin &>/dev/null;
fi; # Travis puts this in ${PATH}.

if [[ ! -d ~/.websharks ]]; then
  mkdir ~/.websharks &>/dev/null;
fi;

# ----------------------------------------------------------------------------------------------------------------------

# Build `pspell` extension for PHP 7 tests (required by websharks/core).
# See: <https://github.com/websharks/core> / <https://github.com/php/php-src>

if [[ "${php_version}" =~ ^7 ]]; then
  if [[ ! -d ~/.websharks/php-src-"${php_exact_version}" ]]; then
    git clone https://github.com/php/php-src ~/.websharks/php-src-"${php_exact_version}" \
      --branch=PHP-"${php_exact_version}" --depth=1 &>/dev/null;
  fi;
  cd ~/.websharks/php-src-"${php_exact_version}"/ext/pspell;
  phpize &>/dev/null; ./configure &>/dev/null; make &>/dev/null; make install &>/dev/null;
fi;

# ----------------------------------------------------------------------------------------------------------------------

# Build the `php.ini` file w/ custom tweaks.
# See: <https://docs.travis-ci.com/user/languages/php>

if [[ ! -f ~/.websharks/php.ini ]]; then
  echo '' > ~/.websharks/php.ini;

  # No PHP headers.
  echo 'expose_php = no' >> ~/.websharks/php.ini;

  # Default timezone.
  echo 'date.timezone = utc' >> ~/.websharks/php.ini;

  # Default charset.
  echo 'default_charset = utf-8' >> ~/.websharks/php.ini;

  # Sessions.
  echo 'session.gc_probability = 1' >> ~/.websharks/php.ini;
  echo 'session.gc_divisor = 500' >> ~/.websharks/php.ini;
  echo 'session.gc_maxlifetime = 86400' >> ~/.websharks/php.ini;

  # Configure error handling.
  echo 'error_reporting = E_ALL' >> ~/.websharks/php.ini;
  echo 'display_startup_errors = yes' >> ~/.websharks/php.ini;
  echo 'display_errors = yes' >> ~/.websharks/php.ini;
  echo 'html_errors = no' >> ~/.websharks/php.ini;

  # Configure assertions.
  echo 'zend.assertions = 0' >> ~/.websharks/php.ini;
  echo 'assert.exception = yes' >> ~/.websharks/php.ini;

  # Default max execution time.
  echo 'max_execution_time = 120' >> ~/.websharks/php.ini;

  # Configure file uploads.
  echo 'upload_max_filesize = 200M' >> ~/.websharks/php.ini;
  echo 'post_max_size = 200M' >> ~/.websharks/php.ini;
  echo 'max_file_uploads = 20' >> ~/.websharks/php.ini;
  echo 'max_input_time = -1' >> ~/.websharks/php.ini;

  # Default max memory limit.
  echo 'memory_limit = 256M' >> ~/.websharks/php.ini;

  # Output buffering.
  echo 'output_buffering = 8096' >> ~/.websharks/php.ini;

  # Caching.
  echo 'realpath_cache_size = 64K' >> ~/.websharks/php.ini;
  echo 'realpath_cache_ttl = 1800' >> ~/.websharks/php.ini;

  # Configure OPcache.
  echo 'opcache.enable = 1' >> ~/.websharks/php.ini;
  echo 'opcache.enable_cli = 1' >> ~/.websharks/php.ini;
  echo 'opcache.memory_consumption = 128' >> ~/.websharks/php.ini;
  echo 'opcache.interned_strings_buffer = 8' >> ~/.websharks/php.ini;
  echo 'opcache.max_accelerated_files = 16229' >> ~/.websharks/php.ini;
  echo 'opcache.max_file_size = 5242880' >> ~/.websharks/php.ini;
  echo 'opcache.revalidate_freq = 60' >> ~/.websharks/php.ini;
  echo 'opcache.fast_shutdown = 1' >> ~/.websharks/php.ini;

  # Disable none.
  echo 'disable_classes =' >> ~/.websharks/php.ini;
  echo 'disable_functions =' >> ~/.websharks/php.ini;

  # PHAR configuration.
  echo 'phar.readonly = no' >> ~/.websharks/php.ini;

  # Preinstalled by Travis. Simply enable.
  echo 'extension = redis.so' >> ~/.websharks/php.ini;
  echo 'extension = memcached.so' >> ~/.websharks/php.ini;

  # PHP 7.0 extension extras.
  if [[ "${php_version}" =~ ^7 ]]; then
    echo 'extension = pspell.so' >> ~/.websharks/php.ini;
  fi;
fi;
phpenv config-add ~/.websharks/php.ini &>/dev/null;
phpenv config-rm xdebug.ini &>/dev/null; # Optimize builds.

# ----------------------------------------------------------------------------------------------------------------------

# Install Phing (and other build dependencies).
# Note: Composer & PHPUnit are already installed by Travis.

if [[ ! -f ~/.websharks/phing ]]; then
  curl http://www.phing.info/get/phing-latest.phar --location --output ~/.websharks/phing &>/dev/null;
  chmod +x ~/.websharks/phing &>/dev/null; # Make it executable.
fi;
ln --symbolic ~/.websharks/phing ~/bin/phing;

if [[ ! -f ~/.websharks/phpcs ]]; then
  curl https://squizlabs.github.io/PHP_CodeSniffer/phpcs.phar --location --output ~/.websharks/phpcs &>/dev/null;
  chmod +x ~/.websharks/phpcs &>/dev/null; # Make it executable.
fi;
ln --symbolic ~/.websharks/phpcs ~/bin/phpcs;

if [[ ! -f ~/.websharks/apigen ]]; then
  curl http://apigen.org/apigen.phar --location --output ~/.websharks/apigen &>/dev/null;
  chmod +x ~/.websharks/apigen &>/dev/null; # Make it executable.
fi;
ln --symbolic ~/.websharks/apigen ~/bin/apigen;

# ----------------------------------------------------------------------------------------------------------------------

# Build all; via Phing.

phing -f "${build_dir}"/build.xml build-all;
