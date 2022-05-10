{% set pget = salt['pillar.get'] %}
# Set a grain
set_rsync_grain:
  grains.list_present:
    - name: roles
    - value: rsync

install_sshpass:
  pkg:
    - name: sshpass
    - installed
    - enablerepo: epel

# Ensure dir exists and perms are correct
/root/.ssh:
  file.directory:
    - user: root
    - group: root
    - mode: 700

# Make sure rsync_id and rsync_id.pub are present
generate_rsync_key:
  cmd.run:
    - name: ssh-keygen -N '' -f /root/.ssh/rsync_id && chmod 600 /root/.ssh/rsync_id.pub
    - creates: /root/.ssh/rsync_id

# SSH Config for rsync, set hostname and user
/root/.ssh/config:
  file.managed:
    - user: root
    - group: root
    - mode: 600
    - template: jinja
    - source: salt://rsync/files/ssh-config
    - context:
        user: {{ pillar['rsync']['user'] }}
    - require_in:
      - cmd: rsync_copy_id

# Add rsync.net known_hosts entry
#rsync_known_host:
#  ssh_known_hosts:
#    - present
#    - user: root
#    - fingerprint: 5f:97:15:54:44:8a:44:7f:ba:8d:b2:ef:51:63:3c:d8
#    - enc: ssh-dss
#    - name: usw-s007.rsync.net

"ssh-keyscan -H usw-s007.rsync.net >> ~/.ssh/known_hosts":
  cmd.run


# Copy ID to rsync.net
rsync_copy_id:
  cmd.run:
    - name: |
        echo '{{ pillar['rsync']['pass'] }}' | sshpass scp /root/.ssh/rsync_id.pub rsyncbackup:.ssh/authorized_keys && touch /root/.ssh/.rsync-copied
    - creates: /root/.ssh/.rsync-copied
    - require: 
      - pkg: sshpass

# List of directories to back up
# First, empty the file
blank-rsync:
  cmd.run:
    - name: '> /etc/rsync-backup.txt'

# Add our paths from pillar
{% for path in pillar['rsync']['paths'] %}
rsync-{{path}}:
  file.append:
    - name: /etc/rsync-backup.txt
    - text: {{ path }}
{% endfor %}

# rsync / db dump script
/opt/rsync/bin:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

/opt/rsync/bin/rsync-backup.sh:
  file.managed:
    - user: root
    - group: root
    - mode: 750
    - source: salt://rsync/files/rsync-backup.sh
    - require:
      - file: /opt/rsync/bin

# cron entry to run script
{% set PK = pget('rsync:pk') %}
{% set TestID = pget('rsync:testid') %}
statuscake_pk:
  cron.env_present:
    - name: PK
    - value: {{PK}}
    - user: root

statuscake_id:
  cron.env_present:
    - name: TestID
    - value: {{TestID}}
    - user: root

#  Enable DB dumps if rsync:dumpdbs is True. Set a default False value if doesn't exist
{% set dumpdbs = salt['pillar.get']('rsync:dumpdbs', False) %}
{% if dumpdbs == True %}
/opt/rsync/bin/rsync-backup.sh dumpdbs 2>&1 | logger -t backups && /usr/bin/curl "https://push.statuscake.com/?PK=$PK&TestID=$TestID&time=0":
  cron.present:
    - identifier: rsyncbackup
    - user: root
    - minute: random
    - hour: 2
{% elif 'mysql' in salt['grains.get']('roles', 'roles:none') %}
/opt/rsync/bin/rsync-backup.sh dumpdbs 2>&1 | logger -t backups && /usr/bin/curl "https://push.statuscake.com/?PK=$PK&TestID=$TestID&time=0":
  cron.present:
    - identifier: rsyncbackup
    - user: root
    - minute: random
    - hour: 2
{% else %}
/opt/rsync/bin/rsync-backup.sh 2>&1 | logger -t backups && /usr/bin/curl "https://push.statuscake.com/?PK=$PK&TestID=$TestID&time=0":
  cron.present:
    - identifier: rsyncbackup
    - user: root
    - minute: random
    - hour: 2
{% endif %}