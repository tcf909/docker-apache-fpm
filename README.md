#Apache+PHP(FPM)
A simple apache+php container that has the following features / modifications:
+ PHP runs in FPM mode and is accessed by Apache via local unix socket (fast)
+ PHP uses ondemand scaling mode to keep the memory footprint low for mostly idle sites (helps container density)
+ PHP various tunings to reduce memory consumption (opcache)
+ Apache is setup with "X-Forwarded-Proto" to support SSL termination and a reverse proxy front end (used with nginx for reverse proxy and ssl offload)
-----------

/var/www/html is used for the primary site (-v "/host/folder:/var/www/html")

Additional vhosts can be dropped in to /etc/apache2/sites-enabled (configmap mounts typically)

To override the default vhost you need to overwrite /etc/apache2/sites-enabled/000-default.conf (configmap mount override)

This container is primarily used in a Kubernetes cluster. We have both NFS based scale out sites and single container
sites using this image. We currently run a farm of Nginx servers as reverse proxies for SSL offloading as well as load balancing. 

Most of the Dockerfile build code was brought over from the official PHP and Apache projects and customized to suit
our needs. 

Feel free to open up an [issue](https://github.com/tcf909/docker-apache-fpm/issues) any questions or issues.