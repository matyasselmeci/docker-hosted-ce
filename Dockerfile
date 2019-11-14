FROM opensciencegrid/software-base:fresh
LABEL maintainer "Lincoln Bryant <lincolnb@uchicago.edu>"

RUN yum install -y yum-plugin-priorities
RUN yum install -y osg-ca-certs osg-ce-bosco fetch-crl gratia-probes-cron openssh openssh-clients certbot

COPY hosted-ce-setup.sh /etc/osg/image-config.d/hosted-ce-setup.sh
#COPY hosted-ce.conf /etc/supervisord.d/hosted-ce.conf
COPY remote-site-setup.sh /etc/osg/remote-site-setup.sh

# can be dropped when provided by upstream htcondor-ce packaging
COPY 51-gratia.conf /usr/share/condor-ce/config.d/51-gratia.conf

# can be dropped when provided by upstream htcondor-ce packaging
RUN mkdir -p /etc/condor-ce/bosco_override

# can be dropped when these are upstreamed to htcondor-ce
COPY bosco-cluster-remote-hosts.sh /usr/local/bin/bosco-cluster-remote-hosts.sh
COPY bosco-cluster-remote-hosts.py /usr/local/bin/bosco-cluster-remote-hosts.py

# do the bad thing of overwriting the existing cron job for fetch-crl
ADD fetch-crl /etc/cron.d/fetch-crl

# Include script to drain the CE and upload accounting data to prepare for container teardown
COPY drain-ce.sh /usr/local/bin/

# Manage HTCondor-CE with supervisor
COPY 10-htcondor-ce.conf /etc/supervisord.d/

# Add a cron job to run the update-all-wn-clients script (the RPM only ships
# with a systemd timer)
COPY update-wn-clients.cron /etc/cron.d/update-wn.clients.cron

#ENTRYPOINT ["osg-configure","-c"]
ENTRYPOINT ["/usr/local/sbin/supervisord_startup.sh"]
