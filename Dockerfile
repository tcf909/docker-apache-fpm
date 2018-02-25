FROM tcf909/ubuntu-slim
MAINTAINER tcf909@gmail.com

ENV APACHE_CONFDIR /etc/apache2
ENV APACHE_ENVVARS $APACHE_CONFDIR/envvars

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        apache2 && \
    a2enmod proxy proxy_fcgi rewrite && \
    rm -rf /var/lib/apt/lists/*

RUN set -ex \
    # generically convert lines like
    #   export APACHE_RUN_USER=www-data
    # into
    #   : ${APACHE_RUN_USER:=www-data}
    #   export APACHE_RUN_USER
    # so that they can be overridden at runtime ("-e APACHE_RUN_USER=...")
	&& sed -ri 's/^export ([^=]+)=(.*)$/: ${\1:=\2}\nexport \1/' "$APACHE_ENVVARS" \
    # setup directories and permissions
	&& . "$APACHE_ENVVARS" \
	&& for dir in \
		"$APACHE_LOCK_DIR" \
		"$APACHE_RUN_DIR" \
		"$APACHE_LOG_DIR" \
		/var/www/html \
	; do \
		rm -rvf "$dir" \
		&& mkdir -p "$dir" \
		&& chown -R "$APACHE_RUN_USER:$APACHE_RUN_GROUP" "$dir"; \
	done


# logs should go to stdout / stderr
RUN set -ex \
	&& . "$APACHE_ENVVARS" \
	&& ln -sfT /dev/stderr "$APACHE_LOG_DIR/error.log" \
	&& ln -sfT /dev/stdout "$APACHE_LOG_DIR/access.log" \
	&& ln -sfT /dev/stdout "$APACHE_LOG_DIR/other_vhosts_access.log"

RUN { \
        echo '<Proxy "fcgi://127.0.0.1:9000/">'; \
        echo '  ProxySet connectiontimeout=5 timeout=60'; \
        echo '</Proxy>'; \
        echo '<FilesMatch "\.php$">'; \
        echo ' <If "-f %{REQUEST_FILENAME}">'; \
        echo '     SetHandler "proxy:fcgi://127.0.0.1:9000"'; \
        echo ' </If>'; \
        echo '</FilesMatch>'; \
		echo; \
		echo 'DirectoryIndex disabled'; \
		echo 'DirectoryIndex index.php index.html'; \
		echo; \
		echo '<Directory /var/www/>'; \
		echo '  Options -Indexes'; \
		echo '  AllowOverride All'; \
		echo '</Directory>'; \
	} | tee "$APACHE_CONFDIR/conf-available/php-fpm.conf" \
	&& a2enconf php-fpm

WORKDIR /var/www/html

COPY inc/entrypoint inc/run_apache /usr/local/bin/

COPY inc/000-default.conf /etc/apache2/sites-available

RUN chmod +x /usr/local/bin/entrypoint /usr/local/bin/run_apache

EXPOSE 80 443

ENTRYPOINT ["entrypoint"]

CMD ["run_apache"]