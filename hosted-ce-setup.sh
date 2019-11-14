#!/bin/bash

# Condor needs to know the annoying randomly generated kubernetes pod hostname
export GARBAGE_HOSTNAME=$(hostname -f)
echo "SUPERUSERS = \$(SUPERUSERS), condor@daemon.htcondor.org/$GARBAGE_HOSTNAME, root@daemon.htcondor.org/$GARBAGE_HOSTNAME" \
>> /etc/condor-ce/config.d/99-hostname.conf
echo "FRIENDLY_DAEMONS = \$(FRIENDLY_DAEMONS), condor@daemon.htcondor.org/$GARBAGE_HOSTNAME condor@child/$GARBAGE_HOSTNAME" \
>> /etc/condor-ce/config.d/99-hostname.conf 

#kubernetes configmaps arent writeable
stat /tmp/99-local.ini
if [[ $? -eq 0 ]]; then
  cp /tmp/99-local.ini /etc/osg/config.d/99-local.ini
fi

# need to programmatically get users
for user in $(echo $CE_USERS | tr ',' ' '); do
  echo "Adding user $user"
  adduser $user 
  mkdir -p /home/$user/.ssh
  chown $user: /home/$user/.ssh
  ssh-keyscan -H $(echo $ENDPOINT | cut -d'@' -f2) >> /home/$user/.ssh/known_hosts
done

echo "Keyscanning.."
mkdir -p ~/.ssh
ssh-keyscan -H $(echo $ENDPOINT | cut -d'@' -f2) >> ~/.ssh/known_hosts

echo "Trying to populate hostname in 99-local.ini with a better value.."
pushd /etc/osg/config.d
  if [[ -z "$_CONDOR_NETWORK_HOSTNAME" ]]; then
    echo '$_CONDOR_NETWORK_HOSTNAME is empty, just using `hostname`'
    sed -i "s/localhost/$(hostname)/" 99-local.ini
  else
    echo '$_CONDOR_NETWORK_HOSTNAME is nonempty, substituting it in..'
    sed -i "s/localhost/$_CONDOR_NETWORK_HOSTNAME/" 99-local.ini
  fi
popd 

echo "Running OSG configure.."
# Run the OSG Configure script to set up bosco
osg-configure -c

echo "Set up WN clients on remote"
/usr/bin/update-all-remote-wn-clients

# TODO remove this setup script; the update script above should
# take care of this.
echo "Copying setup script to remote side.."
# Run some additional adjustments as per Marco's doc
scp -i /etc/osg/bosco.key /etc/osg/remote-site-setup.sh $ENDPOINT:"~/remote-site-setup.sh"
ssh -i /etc/osg/bosco.key $ENDPOINT sh remote-site-setup.sh

echo "Establishing Let's Encrypt certificate.."
# Cert stuff
# this needs to be automated for renewal
certbot certonly -n --agree-tos --standalone --email $CE_CONTACT -d $CE_HOSTNAME 
ln -s /etc/letsencrypt/live/$CE_HOSTNAME/cert.pem /etc/grid-security/hostcert.pem
ln -s /etc/letsencrypt/live/$CE_HOSTNAME/privkey.pem /etc/grid-security/hostkey.pem

echo ">>>>> YOUR CERTIFICATE INFORMATION IS:"
openssl x509 -in /etc/letsencrypt/live/$CE_HOSTNAME/cert.pem -noout -text
echo "><><><><><><><><><><><><><><><><><><><"

/usr/local/bin/bosco-cluster-remote-hosts.sh

echo "Copying local submit attributes file if it exists.."
if [[ -z "$LOCAL_ATTRIBUTES_FILE" ]]; then
  echo "No local submit attributes found"
else
  echo "transferring $LOCAL_ATTRIBUTES_FILE to remote side.."
  scp -i /etc/osg/bosco.key $LOCAL_ATTRIBUTES_FILE $ENDPOINT:"~/bosco/glite/bin/$LOCAL_ATTRIBUTES_FILE"
fi

echo "Enabling WN client updater cron job"
mv /tmp/update-wn-clients.cron /etc/cron.d/update-wn-clients.cron

