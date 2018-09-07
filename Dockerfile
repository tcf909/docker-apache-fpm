FROM tcf909/ubuntu-slim
MAINTAINER tcf909@gmail.com

ENV APACHE_CONFDIR /etc/apache2
ENV APACHE_ENVVARS $APACHE_CONFDIR/envvars

ENV PHP_VERSION 7.2.9
ENV PHP_URL="https://secure.php.net/get/php-7.2.9.tar.xz/from/this/mirror"
ENV PHP_SHA256="3585c1222e00494efee4f5a65a8e03a1e6eca3dfb834814236ee7f02c5248ae0"
ENV PHP_INI_DIR "/etc/php"

#APACHE
EXPOSE 80 443

RUN set -ex; \
    apt-get update; \
    apt-get install --no-install-recommends -y \
        apache2; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/*; \
#Apache Modules
    a2enmod proxy proxy_fcgi rewrite; \
# generically convert lines like
#   export APACHE_RUN_USER=www-data
# into
#   : ${APACHE_RUN_USER:=www-data}
#   export APACHE_RUN_USER
# so that they can be overridden at runtime ("-e APACHE_RUN_USER=...")
	sed -ri 's/^export ([^=]+)=(.*)$/: ${\1:=\2}\nexport \1/' "$APACHE_ENVVARS"; \
# setup directories and permissions
	. "$APACHE_ENVVARS"; \
	for dir in \
		"$APACHE_LOCK_DIR" \
		"$APACHE_RUN_DIR" \
		"$APACHE_LOG_DIR" \
		/var/www/html \
	; do \
		rm -rvf "$dir"; \
		mkdir -p "$dir"; \
	    chown -R "$APACHE_RUN_USER:$APACHE_RUN_GROUP" "$dir"; \
	done; \
#Redirect logs
	ln -sfT /dev/stderr "$APACHE_LOG_DIR/error.log"; \
    ln -sfT /dev/stdout "$APACHE_LOG_DIR/access.log"; \
    ln -sfT /dev/stdout "$APACHE_LOG_DIR/other_vhosts_access.log"

#RUN { \
#        echo 'RewriteEngine On'; \
#        echo 'RewriteCond %{REQUEST_FILENAME} !-d'; \
#        echo 'RewriteCond %{REQUEST_FILENAME} !-f'; \
#        echo 'RewriteRule ^ index.php [L]'; \
#	} | tee "$APACHE_CONFDIR/conf-available/missing-file-redirect.conf" \
#	&& a2enconf missing-file-redirect

#RUN { \
#        echo 'Protocols h2c http/1.1'; \
#	} | tee "$APACHE_CONFDIR/conf-available/http1_1.conf" \
#	&& a2enconf http1_1

COPY rootfs/usr/local/bin/docker-php* /usr/local/bin/

ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -Wl,--hash-style=both -pie"

#PHP
# persistent / runtime deps
RUN set -ex; \
    # prevent Debian's PHP packages from being installed
    # https://github.com/docker-library/php/pull/542
	{ \
		echo 'Package: php*'; \
		echo 'Pin: release *'; \
		echo 'Pin-Priority: -1'; \
	} > /etc/apt/preferences.d/no-debian-php; \
    apt-get update; \
    apt-get install --no-install-recommends -y \
		autoconf \
        dpkg-dev \
        file \
        g++ \
        gcc \
        libc-dev \
        make \
        pkg-config \
        re2c \
		ca-certificates \
		curl \
		xz-utils \
		libfreetype6-dev \
        libicu-dev \
        libjpeg-dev \
        libmcrypt-dev \
        libpng12-dev \
        libpq-dev; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/*;

#BUILD
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libcurl4-openssl-dev \
		libedit-dev \
		libsodium-dev \
		libsqlite3-dev \
		libssl-dev \
		libxml2-dev \
		zlib1g-dev \
		libbz2-dev \
		libmysqlclient-dev; \
#argon2 for ubuntu xenialcd
    sed -e "s/$(lsb_release -cs)/cosmic/g" /etc/apt/sources.list > /etc/apt/sources.list.d/cosmic.list; \
    { \
        echo 'Package: *'; \
        echo 'Pin: release n=cosmic'; \
        echo 'Pin-Priority: -10'; \
        echo; \
        echo 'Package: libargon2*'; \
        echo 'Pin: release n=cosmic'; \
        echo 'Pin-Priority: 990'; \
    } > /etc/apt/preferences.d/argon2-cosmic; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libargon2-dev; \
#argon2
	rm -rf /var/lib/apt/lists/*; \
	\
	#DOWNLOAD PHP
	mkdir -p /usr/src/php; \
	cd /usr/src; \
	wget -O php.tar.xz "$PHP_URL"; \
    echo "$PHP_SHA256 *php.tar.xz" | sha256sum -c -; \
    docker-php-source extract; \
	cd /usr/src/php; \
	\
	# Apply stack smash protection to functions using local buffers and alloca()
    # Make PHP's main executable position-independent (improves ASLR security mechanism, and has no performance impact on x86_64)
    # Enable optimization (-O2)
    # Enable linker optimization (this sorts the hash buckets to improve cache locality, and is non-default)
    # Adds GNU HASH segments to generated executables (this is used if present, and is much faster than sysv hash; in this configuration, sysv hash is also generated)
    # https://github.com/docker-library/php/issues/272
   export \
   		CFLAGS="$PHP_CFLAGS" \
   		CPPFLAGS="$PHP_CPPFLAGS" \
   		LDFLAGS="$PHP_LDFLAGS"; \
    \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
	debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
# https://bugs.php.net/bug.php?id=74125
	if [ ! -d /usr/include/curl ]; then \
		ln -sT "/usr/include/$debMultiarch/curl" /usr/local/include/curl; \
	fi; \
	mkdir -p "${PHP_INI_DIR}/conf.d"; \
	./configure \
		--build="$gnuArch" \
		--sysconfdir="${PHP_INI_DIR}" \
		--with-config-file-path="${PHP_INI_DIR}" \
		--with-config-file-scan-dir="${PHP_INI_DIR}/conf.d" \
# make sure invalid --configure-flags are fatal errors intead of just warnings
		--enable-option-checking=fatal \
# https://github.com/docker-library/php/issues/439
		--with-mhash \
# --enable-ftp is included here because ftp_ssl_connect() needs ftp to be compiled statically (see https://github.com/docker-library/php/issues/236)
		--enable-ftp \
# --enable-mbstring is included here because otherwise there's no way to get pecl to use it properly (see https://github.com/docker-library/php/issues/195)
		--enable-mbstring \
# --enable-mysqlnd is included here because it's harder to compile after the fact than extensions are (since it's a plugin for several extensions, not an extension in itself)
		--enable-mysqlnd \
# https://wiki.php.net/rfc/argon2_password_hash (7.2+)
		--with-password-argon2 \
# https://wiki.php.net/rfc/libsodium
		--with-sodium \
		--with-curl \
		--with-libedit \
		--with-openssl \
		--with-zlib \
# bundled pcre does not support JIT on s390x
# https://manpages.debian.org/stretch/libpcre3-dev/pcrejit.3.en.html#AVAILABILITY_OF_JIT_SUPPORT
		$(test "$gnuArch" = 's390x-linux-gnu' && echo '--without-pcre-jit') \
		--with-libdir="lib/$debMultiarch" \
		--enable-fpm \
		--with-fpm-user=www-data \
		--with-fpm-group=www-data \
		--disable-cgi; \
	make -j "$(nproc)"; \
	make install; \
#Additional modules
	docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ --with-png-dir=/usr; \
    docker-php-ext-install gd opcache bz2 calendar iconv intl mbstring mysqli pdo_mysql pdo_pgsql pgsql zip; \
    pecl install mcrypt-1.0.1; \
    docker-php-ext-enable mcrypt; \
	find /usr/local/bin /usr/local/sbin -type f -executable -exec strip --strip-all '{}' + || true; \
	make clean; \
	cd /; \
	docker-php-source delete \
#CLEAN UP
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
	find /usr/local -type f -executable -exec ldd '{}' ';' \
		| awk '/=>/ { print $(NF-1) }' \
		| sort -u \
		| xargs -r dpkg-query --search \
		| cut -d: -f1 \
		| sort -u \
		| xargs -r apt-mark manual; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/*; \
	\
#Make sure PHP is working
	php --version; \
	\
# https://github.com/docker-library/php/issues/443
	pecl update-channels; \
	rm -rf /tmp/pear ~/.pearrc; \
#Handle fpm.ini
    cd "${PHP_INI_DIR}"; \
    sed "s!=NONE!=!g" php-fpm.conf.default | tee php-fpm.conf > /dev/null; \
    rm php-fpm.conf.default; \
    rm php-fpm.d/www.conf.default;

COPY rootfs/ /