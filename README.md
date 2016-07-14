MySync backup script
====================

This is a very basic script I use to maintain backup of all my evolving file
systems such as SQL databases, SVN repositories, etc. It should be added to
your crontab (or any other task scheduler) and executed hourly (or any interval
you like, this depends on your rules, as you'll see below).

To use it you should first review global configuration file (mysync.conf) and
more precisely the "sources" parameter which indicates where your rules files
are stored. Rules files contain instructions about how to create backup files,
how often and how many previous versions you want to keep. Each line in a rules
file is a rule that should include four space-separated fields:

- name: a unique name for your command (will be used in backup file names)
- save interval: how often a new backup should be created, in seconds
- keep delay: for how much time backup files should be kept, in seconds
- command: a shell command responsible for creating the output backup file

The first three parameters are quite straightforward, but the last one may
require some details. Your command must generate a single archive file from
any source you want, and should use '{}' as the target archive file name. Each
time the command is executed, this special '{}' token is replaced by a unique
path within MySync output directory (see "target" parameter in global
configuration file). Let's take a simple rule example:

webdata		3600	3	cd /var/www && tar -czf {} *

This rule named "webdata" will be executed if last backup file is older than
one hour (3600 seconds) and will keep the last 3 backup files generated this
way. When command is executed, '{}' will be replaced by a unique path within
MySync output directory, e.g. ~mysync/1329725196.webdata.

With this rule, if mysync is executed at least once per hour (but less often as
it couldn't execute your rule every hour otherwise), it will execute "tar"
program to create hourly compressed backup archives of your /var/www folder
and only keep the 3 last generated ones.

You can add comments to configuration & rule files by starting any line with
a '#' character.

Feel free to contact me for any question: github.com [at] mirari [dot] com.
Remi
