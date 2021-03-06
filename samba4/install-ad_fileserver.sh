#!/bin/bash

# source helper functions
. ../helperfunctions.sh

# source configuration
. ../OPTIONS.conf

# install samba4 ad controller
if [ ! "$FULLINSTALL" = "true" ];
then
	echo "FULLINSTALL=false"
	apt-get -y update
fi

printAndLogStartMessage "START: INSTALLATION OF SAMBA4 FILE - SERVER"

export DEBIAN_FRONTEND=noninteractive

printAndLogStartMessage "CHECK /etc/hosts FOR FQDN & STATIC IP"
## check if FQDN exists in /etc/hosts
if [ $(hostname) = $(hostname --fqdn) ];
then
        /bin/bash change-FQHN-etc_hosts.sh
fi
## set STATIC IP in /etc/hosts
/bin/bash change-IP-etc_hosts.sh

printAndLogMessage "INSTALL PACKAGES"
printAndLogMessage "acl attr samba samba-dsdb-modules samba-vfs-modules winbind krb5-config krb5-user bind9-dnsutils ldb-tools adcli"
## from samba - wiki: acl attr samba samba-dsdb-modules samba-vfs-modules winbind krb5-config krb5-user
## acl, attr: exteded acls
## bind9-dnsutils: dig, nslookup
## to get Domain Users/Groups onto Fileserver to set Directory/File Permissions: libnss-winbind
## to enable local logins for Domain Users: libpam-winbind
## to preset computer-accounts: adcli
## to act as nfs-server: nfs-kernel-server
apt-get install -y acl attr samba samba-dsdb-modules samba-vfs-modules winbind krb5-config krb5-user bind9-dnsutils libnss-winbind libpam-winbind adcli nfs-kernel-server

##STOP AND DISABLE systemd-resolved & SET AD DOMAIN CONTROLLER IP AS NAMESERVER IN NEW $file"
/bin/bash change-etc_resolv.conf.sh  

### WRITE NEW CLEAN KERBEROS CONFIGURATION FILES
/bin/bash write-etc_krb5.conf.sh

## WRITE NEW /etc/samba/smb.conf
/bin/bash write-etc_samba_smb.conf.sh

## CONNECT client via nsswitch.conf and winbind to domain ${SAMBA4_DOMAIN}
/bin/bash change-etc_nsswitch.conf.sh

## restart winbind
printAndLogMessage "systemctl restart winbind"
systemctl restart winbind

## enable automatic home-directory creation
printAndLogMessage "enable automatic home-directory creation"
pam-auth-update --enable mkhomedir

printAndLogMessage "join domain ${SAMBA4_REALM_DOMAIN_NAME}"
# adcli join -v --one-time-password=secret1234 ${SAMBA4_REALM_DOMAIN_NAME}
# looks like adcli works only with sssd without problems :-( ??
# so we use net ads on servers
# server will also be added to DNS, if it does not exist. error message if allready in DNS
net ads join -U Administrator@${SAMBA4_DNS_DOMAIN_NAME}%${SAMBA4_ADMINISTRATOR_PASSWORD}

printAndLogMessage "create directory for users ${SAMBA4_HOMES_BASE_DIR}/users/"
mkdir -p ${SAMBA4_HOMES_BASE_DIR}/users/

printAndLogMessage "change group to Domain Users for ${SAMBA4_HOMES_BASE_DIR}/users/"
chgrp -v "${SAMBA4_DOMAIN}\Domain Admins" ${SAMBA4_HOMES_BASE_DIR}/users/

printAndLogMessage "change mode for directory ${SAMBA4_HOMES_BASE_DIR}/users/"
chmod -v 2775 ${SAMBA4_HOMES_BASE_DIR}/users/

printAndLogMessage "add share /home/xchange/"
/bin/bash add_share_xchange-etc_samba_smb.conf.sh


#### ADD NFS - Server START ####
cd ../nfs-server
printAndLogMessage "add nfs-shares"
/bin/bash install-nfs_server.sh
cd ../samba4

mkdir -p $NFS_EXPORT_DIR/users

mount --bind ${SAMBA4_HOMES_BASE_DIR}/users/ $NFS_EXPORT_DIR/users

printAndLogMessage "MOUNT ${SAMBA4_HOMES_BASE_DIR}/users/ TO EXPORTS DIRECTORY $NFS_EXPORT_DIR/users"
/bin/bash change-etc_fstab.sh

printAndLogMessage "ADD $NFS_EXPORT_DIR/users TO /etc/exports"
/bin/bash change-etc_exports.sh
#### ADD NFS - Server END ####


printAndLogEndMessage "FINISH:  INSTALLATION OF SAMBA4 FILE - SERVER"


