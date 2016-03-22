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

# Parse, export & satisfy CI run vars.

IFS=',' read -r -a _ci_run <<< "${CI_RUN}";
for _ci_run_var in "${_ci_run[@]}"; do
    export CI_RUN_"${_ci_run_var%%=*}"="${_ci_run_var#*=}" &>/dev/null;
done; unset _ci_run; unset _ci_run_var;

export CI_RUN_PHP_VERSION; CI_RUN_PHP_VERSION="$(php -r 'echo PHP_VERSION;')" &>/dev/null;
export CI_RUN_MYSQL_VERSION; CI_RUN_MYSQL_VERSION="$(mysql --version)" &>/dev/null;

if [[ -n "${CI_RUN_WP}" ]]; then
  if [[ -z "${CI_RUN_WP_VERSION}" || "${CI_RUN_WP_VERSION}" == 'latest' ]]; then
    CI_RUN_WP_VERSION='$json = json_decode(file_get_contents("https://api.wordpress.org/core/version-check/1.7/"));';
    CI_RUN_WP_VERSION+='echo !empty($json->offers[0]->version) ? $json->offers[0]->version : "";';
    CI_RUN_WP_VERSION="$(php -r "${CI_RUN_WP_VERSION}")";
  elif [[ "${CI_RUN_WP_VERSION}" == 'nightly' ]]; then
    CI_RUN_WP_VERSION="$(date +%Y%m%d)"-nightly;
  fi;
fi;
# ----------------------------------------------------------------------------------------------------------------------

# Preamble with several build details.
echo; # First line is a spacer from other Travis details.
echo '--- CI Preamble ------------------------------------------------------';
echo;
echo 'Run vars: '"${CI_RUN}";
echo;
echo 'PHP Version: '"${CI_RUN_PHP_VERSION}";
echo;
echo 'MySQL Version: '"${CI_RUN_MYSQL_VERSION}";
echo 'MySQL DB Host: '"${CI_CFG_MYSQL_DB_HOST}";
echo 'MySQL DB Port: '"${CI_CFG_MYSQL_DB_PORT}";
echo 'MySQL DB Charset: '"${CI_CFG_MYSQL_DB_CHARSET}";
echo 'MySQL DB Collate: '"${CI_CFG_MYSQL_DB_COLLATE}";
echo 'MySQL DB Username: '"${CI_CFG_MYSQL_DB_USERNAME}";
echo 'MySQL DB Password: '"${CI_CFG_MYSQL_DB_PASSWORD}";
echo 'MySQL DB Name: '"${CI_CFG_MYSQL_DB_NAME}";
echo;
echo 'Build Host: '"${CI_CFG_BUILD_HOST}";
echo 'Build Port: '"${CI_CFG_BUILD_PORT}";
echo 'Build URL: '"${CI_CFG_BUILD_URL}";
echo 'Build Dir: '"${CI_CFG_BUILD_DIR}";
echo 'Build Dir Basename: '"${CI_CFG_BUILD_DIR_BASENAME}";

if [[ -n "${CI_RUN_WP}" ]]; then
  echo;
  echo 'WordPress Version: '"${CI_RUN_WP_VERSION}";
  echo 'WordPress Host: '"${CI_CFG_WP_HOST}";
  echo 'WordPress Port: '"${CI_CFG_WP_PORT}";
  echo 'WordPress URL: '"${CI_CFG_WP_URL}";
  echo 'WordPress Dir: '"${CI_CFG_WP_DIR}";
  echo 'WordPress DB Prefix: '"${CI_CFG_WP_DB_PREFIX}";
  echo 'WordPress Admin: '"${CI_CFG_WP_ADMIN}";
fi;
echo;
# ----------------------------------------------------------------------------------------------------------------------

echo '--- Installing Required Software -------------------------------------';
echo; # This could take a minute or two.
echo 'one moment please...'; # Indicate progress.
echo; # Output stops here for installation processes; i.e., `&>/dev/null` used below.

# ----------------------------------------------------------------------------------------------------------------------

# Create directories (including a `.persistent` cache).
# See: <https://docs.travis-ci.com/user/caching/>

mkdir --parents ~/bin &>/dev/null; # in `${PATH}`.

mkdir --parents ~/ws/apps &>/dev/null;
mkdir --parents ~/ws/binaries &>/dev/null;
mkdir --parents ~/ws/cache &>/dev/null;
mkdir --parents ~/ws/configs &>/dev/null;
mkdir --parents ~/ws/logs &>/dev/null;
mkdir --parents ~/ws/logs/php &>/dev/null;
mkdir --parents ~/ws/tmp &>/dev/null;
mkdir --parents ~/ws/repos &>/dev/null;

mkdir --parents ~/ws/.persistent/apps &>/dev/null;
mkdir --parents ~/ws/.persistent/binaries &>/dev/null;
mkdir --parents ~/ws/.persistent/configs &>/dev/null;
mkdir --parents ~/ws/.persistent/repos &>/dev/null;

mkdir --parents "${CI_CFG_LOGS_DIR}" &>/dev/null;
mkdir --parents "${CI_CFG_CACHE_DIR}" &>/dev/null;

if [[ -n "${CI_RUN_WP}" ]]; then
  mkdir --parents "${CI_CFG_WP_DIR}" &>/dev/null;
fi;
# ----------------------------------------------------------------------------------------------------------------------

# Build `pspell` extension via `phpize` since it's not possible to alter the `./configure` line.
# See: <https://github.com/websharks/core> / <https://github.com/php/php-src>

if [[ ! -d ~/ws/.persistent/repos/php-src-"${CI_RUN_PHP_VERSION}" ]]; then
  git clone https://github.com/php/php-src ~/ws/.persistent/repos/php-src-"${CI_RUN_PHP_VERSION}" --branch=PHP-"${CI_RUN_PHP_VERSION}" --depth=1 &>/dev/null;
fi;
cp --force --recursive ~/ws/.persistent/repos/php-src-"${CI_RUN_PHP_VERSION}"/. ~/ws/repos/php-src-"${CI_RUN_PHP_VERSION}" &>/dev/null;

cd ~/ws/repos/php-src-"${CI_RUN_PHP_VERSION}"/ext/pspell &>/dev/null;
phpize &>/dev/null; ./configure &>/dev/null; make &>/dev/null; make install &>/dev/null;

# ----------------------------------------------------------------------------------------------------------------------

# Build the `php.ini` file w/ custom tweaks.
# See: <https://docs.travis-ci.com/user/languages/php>

if [[ ! -f ~/ws/.persistent/configs/php.ini ]]; then
  curl https://raw.githubusercontent.com/websharks/ubuntu-bootstrap/master/src/php/.ini --location --output ~/ws/.persistent/configs/php.ini &>/dev/null;
fi;
cp ~/ws/.persistent/configs/php.ini ~/ws/configs/php.ini &>/dev/null;

echo 'extension = redis.so' >> ~/ws/configs/php.ini;
echo 'extension = memcached.so' >> ~/ws/configs/php.ini;
echo 'extension = pspell.so' >> ~/ws/configs/php.ini;

echo 'phar.readonly = no' >> ~/ws/configs/php.ini;
echo 'auto_prepend_file =' >> ~/ws/configs/php.ini;
echo 'error_log = '"${HOME}"'/ws/logs/php/errors.log' >> ~/ws/configs/php.ini;
echo 'sendmail_path = "/usr/sbin/sendmail -t -i"' >> ~/ws/configs/php.ini;

phpenv config-rm xdebug.ini &>/dev/null;
phpenv config-add ~/ws/configs/php.ini &>/dev/null;

# ----------------------------------------------------------------------------------------------------------------------

# Install utilities like Phing, PHP CS, APIGEN, etc.
# Note: Composer & PHPUnit are already installed by Travis.

if [[ ! -f ~/ws/.persistent/binaries/phing ]]; then
  curl http://www.phing.info/get/phing-latest.phar --location --output ~/ws/.persistent/binaries/phing &>/dev/null;
  chmod +x ~/ws/.persistent/binaries/phing &>/dev/null;
fi;
ln --symbolic ~/ws/.persistent/binaries/phing ~/bin/phing &>/dev/null;

if [[ ! -f ~/ws/.persistent/binaries/phpcs ]]; then
  curl https://squizlabs.github.io/PHP_CodeSniffer/phpcs.phar --location --output ~/ws/.persistent/binaries/phpcs &>/dev/null;
  chmod +x ~/ws/.persistent/binaries/phpcs &>/dev/null;
fi;
ln --symbolic ~/ws/.persistent/binaries/phpcs ~/bin/phpcs &>/dev/null;

if [[ ! -f ~/ws/.persistent/binaries/apigen ]]; then
  curl http://apigen.org/apigen.phar --location --output ~/ws/.persistent/binaries/apigen &>/dev/null;
  chmod +x ~/ws/.persistent/binaries/apigen &>/dev/null;
fi;
ln --symbolic ~/ws/.persistent/binaries/apigen ~/bin/apigen &>/dev/null;

if [[ -n "${CI_RUN_WP}" ]]; then
  if [[ ! -f ~/ws/.persistent/binaries/wp ]]; then
    curl https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar --location --output ~/ws/.persistent/binaries/wp &>/dev/null;
    chmod +x ~/ws/.persistent/binaries/wp &>/dev/null;
  fi;
  ln --symbolic ~/ws/.persistent/binaries/wp ~/bin/wp &>/dev/null;

  echo '' > ~/ws/configs/wp-cli.yml;
  echo 'user: '"${CI_CFG_WP_ADMIN}" >> ~/ws/configs/wp-cli.yml;
  echo 'path: '"${CI_CFG_WP_DIR}" >> ~/ws/configs/wp-cli.yml;
  echo 'url: '"${CI_CFG_WP_URL}" >> ~/ws/configs/wp-cli.yml;

  mkdir --parents ~/.wp-cli &>/dev/null;
  ln --symbolic ~/ws/configs/wp-cli.yml ~/.wp-cli/config.yml &>/dev/null;
fi;
# ----------------------------------------------------------------------------------------------------------------------

# Install MySQL database.

mysql --user=root --execute="GRANT ALL ON *.* TO '${CI_CFG_MYSQL_DB_USERNAME}'@'localhost' IDENTIFIED BY '${CI_CFG_MYSQL_DB_PASSWORD}';" &>/dev/null;
mysql --user=root --execute="GRANT ALL ON *.* TO '${CI_CFG_MYSQL_DB_USERNAME}'@'${CI_CFG_MYSQL_DB_HOST}' IDENTIFIED BY '${CI_CFG_MYSQL_DB_PASSWORD}';" &>/dev/null;
mysql --user=root --execute="CREATE DATABASE \`${CI_CFG_MYSQL_DB_NAME}\` CHARACTER SET '${CI_CFG_MYSQL_DB_CHARSET}' COLLATE '${CI_CFG_MYSQL_DB_COLLATE}';" &>/dev/null;
mysql --user=root --execute="FLUSH PRIVILEGES;" &>/dev/null;

# ----------------------------------------------------------------------------------------------------------------------

# Maybe configure & install WordPress (standard|multisite).

if [[ -n "${CI_RUN_WP}" ]]; then
  if [[ ! -d ~/ws/.persistent/apps/wp-"${CI_RUN_WP_VERSION}" ]]; then
    mkdir ~/ws/.persistent/apps/wp-"${CI_RUN_WP_VERSION}" &>/dev/null;

    if [[ "${CI_RUN_WP_VERSION}" =~ \-nightly$ ]]; then
      curl https://wordpress.org/nightly-builds/wordpress-latest.zip --location --output ~/ws/tmp/wordpress-nightly.zip;
      unzip -qq -d ~/ws/tmp/wordpress-nightly ~/ws/tmp/wordpress-nightly.zip;
      cp --force --recursive ~/ws/tmp/wordpress-nightly/wordpress/. ~/ws/.persistent/apps/wp-"${CI_RUN_WP_VERSION}";
      rm --force --recursive ~/ws/tmp/wordpress-nightly;
      rm ~/ws/tmp/wordpress-nightly.zip;
    else # We can just use WP-CLI to download a specific version.
      wp core download --version="${CI_RUN_WP_VERSION}" --path="${HOME}"/ws/.persistent/apps/wp-"${CI_RUN_WP_VERSION}" &>/dev/null;
    fi;
  fi;
  for _wp_run in standard multisite; do

    # Work out conditional variables; else continue if n/a.

    if [[ "${CI_RUN_WP}" == 'multisite' && "${CI_RUN_WP}" == "${_wp_run}" ]]; then
      _wp_install_command='multisite-install';

    elif [[ "${CI_RUN_WP}" == 'standard' && "${CI_RUN_WP}" == "${_wp_run}" ]]; then
      _wp_install_command='install';

    else continue; fi; # Bypass; not applicable.

    # Copy WordPress core files.

    cp --force --recursive ~/ws/.persistent/apps/wp-"${CI_RUN_WP_VERSION}" "${CI_CFG_WP_DIR}" &>/dev/null;

    # Generate a `/wp-config.php` file.

    wp core config --dbhost="${CI_CFG_MYSQL_DB_HOST}":"${CI_CFG_MYSQL_DB_PORT}" \
      --dbname="${CI_CFG_MYSQL_DB_NAME}" --dbprefix="${CI_CFG_WP_DB_PREFIX}" \
      --dbcharset="${CI_CFG_MYSQL_DB_CHARSET}" --dbcollate="${CI_CFG_MYSQL_DB_COLLATE}" \
      --dbuser="${CI_CFG_MYSQL_DB_USERNAME}" --dbpass="${CI_CFG_MYSQL_DB_PASSWORD}";

    # Install WordPress DB tables, etc.

    wp core "${_wp_install_command}" --title=WordPress --admin_user="${CI_CFG_WP_ADMIN}" --admin_password="${CI_CFG_WP_ADMIN}" \
      --admin_email=travis-ci+admin@wsharks.com --skip-email &>/dev/null;

    # Create 2 users w/ each default role (10 users total).

    for _wp_role in administrator editor author contributor subscriber; do
      for _wp_user_i in {1..2}; do
        wp user create "${_wp_role}${_wp_user_i}" travis-ci+"${_wp_role}${_wp_user_i}"@wsharks.com --user_pass="${_wp_role}${_wp_user_i}" --role="${_wp_role}" \
          --first_name=Test --last_name="${_wp_role^}${_wp_user_i}" --display_name='Test '"${_wp_role^}${_wp_user_i}" &>/dev/null;
      done; unset _wp_user_i;
    done; unset _wp_role;

    # Create 2 additional users (generic subscribers) for testing purposes.

    for _wp_user_i in {1..2}; do
      wp user create user"${_wp_user_i}" travis-ci+user"${_wp_user_i}"@wsharks.com --user_pass=user"${_wp_user_i}" --role=subscriber \
        --first_name=Test --last_name=User"${_wp_user_i}" --display_name='Test User'"${_wp_user_i}" &>/dev/null;
    done; unset _wp_user_i;

    # If multisite, create 2 child sites & add users to those sites.

    if [[ "${CI_RUN_WP}" == 'multisite' ]]; then
      for _wp_site_i in {1..2}; do
        wp site create --slug=site"${_wp_site_i}" --title=Site"${_wp_site_i}" &>/dev/null;

        for _wp_role in administrator editor author contributor subscriber; do
          for _wp_user_i in {1..2}; do
            wp user set-role "${_wp_role}${_wp_user_i}" "${_wp_role}" --url="${CI_CFG_WP_URL}"/site"${_wp_site_i}" &>/dev/null;
          done; unset _wp_user_i;
        done; unset _wp_role;

        for _wp_user_i in {1..2}; do
          wp user set-role user"${_wp_user_i}" subscriber --url="${CI_CFG_WP_URL}"/site"${_wp_site_i}" &>/dev/null;
        done; unset _wp_user_i;
      done; unset _wp_site_i;
    fi;
    # If this is a WP theme or plugin; symlink & activate.

    if [[ -f "${CI_CFG_BUILD_DIR}"/readme.txt ]]; then

      # If this is a WordPress plugin.

      if [[ -f "${CI_CFG_BUILD_DIR}"/plugin.php || -f "${CI_CFG_BUILD_DIR}"/"${CI_CFG_BUILD_DIR_BASENAME}".php ]]; then
        ln --symbolic "${CI_CFG_BUILD_DIR}" "${CI_CFG_WP_DIR}"/wp-content/plugins/"${CI_CFG_BUILD_DIR_BASENAME}" &>/dev/null;

        # Maybe activate network-wide.

        if [[ "${CI_RUN_WP}" == 'multisite' ]]; then
          wp plugin activate "${CI_CFG_BUILD_DIR_BASENAME}" --network &>/dev/null;

        else # Standard plugin activation in this case.
          wp plugin activate "${CI_CFG_BUILD_DIR_BASENAME}" &>/dev/null;
        fi;
      # If this is a WordPress theme.

      elif [[ -f "${CI_CFG_BUILD_DIR}"/style.css || -f "${CI_CFG_BUILD_DIR}"/functions.php ]]; then
        ln --symbolic "${CI_CFG_BUILD_DIR}" "${CI_CFG_WP_DIR}"/wp-content/themes/"${CI_CFG_BUILD_DIR_BASENAME}" &>/dev/null;

        # Maybe enable & activate network-wide.

        if [[ "${CI_RUN_WP}" == 'multisite' ]]; then
          wp theme enable "${CI_CFG_BUILD_DIR_BASENAME}" --network --activate &>/dev/null;

          for _wp_site_i in {1..2}; do
            wp theme activate "${CI_CFG_BUILD_DIR_BASENAME}" --url="${CI_CFG_WP_URL}"/site"${_wp_site_i}" &>/dev/null;
          done; unset _wp_site_i;

        else # Standard theme activation in this case.
          wp theme activate "${CI_CFG_BUILD_DIR_BASENAME}" &>/dev/null;
        fi;
      fi;
    fi;
  done; unset _wp_run; unset _wp_install_command;
fi;
# ----------------------------------------------------------------------------------------------------------------------

# Custom code reinserted here via [custom] marker. Add your <custom></custom> comment markers here please.

# ----------------------------------------------------------------------------------------------------------------------

# Build all; via Phing.

echo '--- Phing Build Process ----------------------------------------------';
echo; # This starts Phing build process.
phing -f "${CI_CFG_BUILD_DIR}"/build.xml build-all;
echo; # If anything fails during the build, Phing exits.

# ----------------------------------------------------------------------------------------------------------------------

# Check for any PHP errors that occurred; e.g., during unit testing.

if [[ -s ~/ws/logs/php/errors.log ]]; then
  echo '--- The following PHP errors were found in the log: ------------------';
  echo; # Display PHP error log for careful review.
  cat ~/ws/logs/php/errors.log; exit 1;
fi;
# ----------------------------------------------------------------------------------------------------------------------

# Complete. Indicate success w/ final output now.

echo '--- Complete ---------------------------------------------------------';
echo; # Indicate success.
echo 'Build success — fantastic!';
