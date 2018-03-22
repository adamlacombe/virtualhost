#!/bin/bash
### Set Language
TEXTDOMAIN=virtualhost

#https://stackoverflow.com/a/28709668/9238321
cecho() {
  local code="\033["
  case "$1" in
    black  | bk) color="${code}0;30m";;
    red    |  r) color="${code}1;31m";;
    green  |  g) color="${code}1;32m";;
    yellow |  y) color="${code}1;33m";;
    blue   |  b) color="${code}1;34m";;
    purple |  p) color="${code}1;35m";;
    cyan   |  c) color="${code}1;36m";;
    gray   | gr) color="${code}0;37m";;
    *) local text="$1"
  esac
  [ -z "$text" ] && local text="$color$2${code}0m"
  echo -e "$text"
}

### Set default parameters
action=$1
domain=$2
rootDir=$3
owner=$(logname)
#apacheUser=$(ps -ef | egrep '(httpd|apache2|apache)' | grep -v root | head -n1 | awk '{print $1}')
apacheUser='www-data'
email='webmaster@localhost'
sitesEnabled='/etc/apache2/sites-enabled/'
sitesAvailable='/etc/apache2/sites-available/'
userDir='/var/www/'
sitesAvailabledomain=$sitesAvailable$domain.conf
gitRepo=""

### don't modify from here unless you know what you are doing ####

if [ "$(whoami)" != 'root' ]; then
	cecho r "You have no permission to run $0 as non-root user. Use sudo"
		exit 1;
fi

if [ "$action" != 'create' ] && [ "$action" != 'delete' ]
	then
		cecho r "You need to prompt for action (create or delete) -- Lower-case only"
		exit 1;
fi

while [ "$domain" == "" ]
do
	cecho y "Please provide domain. e.g.dev,staging"
	read domain
done

if [ "$rootDir" == "" ]; then
	rootDir=${domain//./}
fi

### if root dir starts with '/', don't use /var/www as default starting point
if [[ "$rootDir" =~ ^/ ]]; then
	userDir=''
fi

rootDir=$userDir$rootDir

if [ "$action" == 'create' ]
	then
		### check if domain already exists
		if [ -e $sitesAvailabledomain ]; then
			cecho r "This domain already exists.\nPlease Try Another one"
			exit;
		fi

		while [ "$gitRepo" == "" ]
        do
            cecho y "Please provide the repo you would like to clone. e.g. https://YOUR-NAME@bitbucket.org/YOUR-NAME/REPO-NAME.git"
            read gitRepo
        done

		### check if directory exists or not
		if ! [ -d $rootDir ]; then
			### create the directory
			mkdir $rootDir
			### give permission to root dir
			chmod 755 $rootDir
			### write test file in the new domain dir
			git clone $gitRepo $rootDir/
		fi

		### create virtual host rules file
		if ! echo "
		<VirtualHost *:80>
			ServerAdmin $email
			ServerName $domain
			ServerAlias $domain
			DocumentRoot $rootDir
			<Directory />
				AllowOverride All
			</Directory>
			<Directory $rootDir>
				Options Indexes FollowSymLinks MultiViews
				AllowOverride all
				Require all granted
			</Directory>
			ErrorLog /var/log/apache2/$domain-error.log
			LogLevel error
			CustomLog /var/log/apache2/$domain-access.log combined
		</VirtualHost>" > $sitesAvailabledomain
		then
			cecho r "There is an ERROR creating $domain file"
			exit;
		else
			cecho g "\nNew Virtual Host Created\n"
		fi

		### Add domain in /etc/hosts
		if ! echo "127.0.0.1	$domain" >> /etc/hosts
		then
			cecho r "ERROR: Not able to write in /etc/hosts"
			exit;
		else
			cecho g "Host added to /etc/hosts file \n"
		fi

		### Add domain in /mnt/c/Windows/System32/drivers/etc/hosts (Windows Subsytem for Linux)
		if [ -e /mnt/c/Windows/System32/drivers/etc/hosts ]
		then
			if ! echo -e "\r127.0.0.1       $domain" >> /mnt/c/Windows/System32/drivers/etc/hosts
			then
				cecho r "ERROR: Not able to write in /mnt/c/Windows/System32/drivers/etc/hosts (Hint: Try running Bash as administrator)"
			else
				cecho g "Host added to /mnt/c/Windows/System32/drivers/etc/hosts file \n"
			fi
		fi

		if [ "$owner" == "" ]; then
		    iam=$(whoami)
			if [ "$iam" == "root" ]; then
				chown -R $apacheUser:$apacheUser $rootDir
			else
				chown -R $owner:$apacheUser $rootDir
			fi
		else
			chown -R $owner:$apacheUser $rootDir
		fi

		chmod -R ug+rwx $rootDir

		### enable website
		a2ensite $domain

		### restart Apache
		systemctl restart apache2

		### show the finished message
		cecho g "Complete! \nYou now have a new Virtual Host \nYour new host is: http://$domain \nAnd its located at $rootDir"
		exit;
	else
		### check whether domain already exists
		if ! [ -e $sitesAvailabledomain ]; then
			cecho r "This domain does not exist.\nPlease try another one"
			exit;
		else
			### Delete domain in /etc/hosts
			newhost=${domain//./\\.}
			sed -i "/$newhost/d" /etc/hosts

			### Delete domain in /mnt/c/Windows/System32/drivers/etc/hosts (Windows Subsytem for Linux)
			if [ -e /mnt/c/Windows/System32/drivers/etc/hosts ]
			then
				newhost=${domain//./\\.}
				sed -i "/$newhost/d" /mnt/c/Windows/System32/drivers/etc/hosts
			fi

			### disable website
			a2dissite $domain

			### restart Apache
			systemctl restart apache2

			### Delete virtual host rules files
			rm $sitesAvailabledomain
		fi

		### check if directory exists or not
		if [ -d $rootDir ]; then
			cecho y "Delete host root directory: $rootDir ? (y/n)"
			read deldir

			if [ "$deldir" == 'y' -o "$deldir" == 'Y' ]; then
				### Delete the directory
				rm -rf $rootDir
				cecho g "Directory deleted"
			else
				cecho b "Host directory conserved"
			fi
		else
			cecho r "Host directory not found. Ignored"
		fi

		### show the finished message
		cecho g "Complete!\nYou just removed Virtual Host $domain"
		exit 0;
fi