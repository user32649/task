{% set user = salt['pillar.get']('kartaca:user', {}) %}
{% set timezone = 'Europe/Istanbul' %}
{% set terraform_version = '1.6.4' %}
{% set wp_secret_keys_url = 'https://api.wordpress.org/secret-key/1.1/salt/' %}

create_kartaca_user:
  user.present:
    - name: {{ user.name }}
    - uid: 2023
    - gid: 2023
    - home: /home/krt
    - shell: /bin/bash
    - password: {{ user.password }}
    - groups:
      - sudo

configure_sudoers:
  file.managed:
    - name: /etc/sudoers.d/kartaca
    - source: salt://files/kartaca_sudoers
    - mode: 440

set_timezone:
  timezone.system:
    - name: {{ timezone }}

enable_ip_forwarding:
  sysctl.persisted:
    - name: net.ipv4.ip_forward
    - value: 1

install_required_packages:
  pkg.installed:
    - pkgs:
      - htop
      - traceroute
      - iputils-ping
      - dnsutils
      - sysstat
      - mtr
    - refresh: True

add_hashicorp_repo:
  pkgrepo.managed:
    - humanname: HashiCorp
    - name: deb [arch=amd64] https://apt.releases.hashicorp.com {{ grains['oscodename'] }} main
    - file: /etc/apt/sources.list.d/hashicorp.list
    - dist: {{ grains['oscodename'] }}
    - key_url: https://apt.releases.hashicorp.com/gpg
    - onlyif: grains['os'] == 'Ubuntu'

  pkgrepo.managed:
    - humanname: HashiCorp
    - name: HashiCorp
    - baseurl: https://rpm.releases.hashicorp.com/$releasever/$basearch/stable
    - gpgkey: https://rpm.releases.hashicorp.com/gpg
    - gpgcheck: 1
    - onlyif: grains['os'] == 'CentOS'

install_terraform:
  pkg.installed:
    - name: terraform
    - version: '{{ terraform_version }}*'
    - refresh: True

update_hosts_file:
  {% for ip in range(128, 144) %}
  host.present:
    - name: kartaca.local
    - ip: 192.168.168.{{ ip }}
  {% endfor %}

{% if grains['os'] == 'CentOS' %}
  install_nginx:
    pkg.installed:
      - name: nginx

  configure_nginx:
    service.running:
      - name: nginx
      - enable: True
      - watch:
        - file: /etc/nginx/nginx.conf

  install_php_for_wordpress:
    pkg.installed:
      - pkgs:
        - php
        - php-fpm
        - php-mysqlnd
        - php-gd
        - php-xml

  download_wordpress:
    file.managed:
      - name: /tmp/wordpress.tar.gz
      - source: https://wordpress.org/wordpress-5.7.2.tar.gz

  extract_wordpress:
    archive.extracted:
      - name: /var/www/wordpress2023
      - source: /tmp/wordpress.tar.gz
      - if_missing: /var/www/wordpress2023/wp-config.php

  nginx_configuration:
    file.managed:
      - name: /etc/nginx/nginx.conf
      - source: salt://files/nginx.conf
      - user: root
      - group: root
      - mode: 644
      - require:
        - pkg: install_nginx
      - watch_in:
        - service: nginx

  create_self_signed_ssl:
    cmd.run:
      - name: |
          openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
          -keyout /etc/ssl/private/nginx-selfsigned.key \
          -out /etc/ssl/certs/nginx-selfsigned.crt \
          -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=www.example.com"
      - unless: test -f /etc/ssl/private/nginx-selfsigned.key

  restart_nginx_monthly:
    cron.present:
      - name: "service nginx restart"
      - user: root
      - daymonth: 1
      - hour: 0
      - minute: 0

  nginx_log_rotation:
    file.managed:
      - name: /etc/logrotate.d/nginx
      - source: salt://files/nginx_logrotate
      - user: root
      - group: root
      - mode: 644

{% endif %}

{% if grains['os'] == 'Ubuntu' %}
  install_mysql:
    pkg.installed:
      - name: mysql-server

  configure_mysql:
    service.running:
      - name: mysql
      - enable: True

  mysql_database_setup:
    mysql_database.present:
      - name: wordpress
      - connection_user: root
      - connection_pass: {{ pillar['mysql']['root_password'] }}

  mysql_user_setup:
    mysql_user.present:
      - name: wordpressuser
      - host: localhost
      - password: {{ pillar['mysql']['wordpressuser_password'] }}
      - databases:
        - database: wordpress
          grant: ALL PRIVILEGES

  mysql_cron_backup:
    cron.present:
      - name: "Backup MySQL database"
      - user: root
      - minute: 0
      - hour: 2
      - daymonth: '*'
      - month: '*'
      - dayweek: '*'
      - cmd: "mysqldump -u root -p{{ pillar['mysql']['root_password'] }} wordpress > /backup/wordpress_backup_$(date +\%F).sql"
{% endif %}

