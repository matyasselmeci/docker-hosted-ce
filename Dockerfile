FROM opensciencegrid/software-base:fresh
LABEL maintainer "OSG Software <help@opensciencegrid.org>"

# Impatiently ignore the Yum mirrors
RUN sed -i 's/\#baseurl/baseurl/; s/mirrorlist/\#mirrorlist/' \
           /etc/yum.repos.d/osg-testing.repo

RUN yum install -y --enablerepo=osg-testing \
                   --enablerepo=osg-upcoming-testing \
                   osg-ce-bosco \
                   git \
                   openssh-clients \
                   sudo \
                   wget \
                   certbot \
                   perl-LWP-Protocol-https \
                   # ^^^ for fetch-crl, in the rare case that the CA forces HTTPS
                   patch && \
   # Separate CE View installation to work around Yum depsolving fail
   yum install -y --enablerepo=osg-testing \
                   htcondor-ce-view && \
    yum clean all && \
    rm -rf /var/cache/yum/

COPY 25-hosted-ce-setup.sh /etc/osg/image-config.d/
COPY 30-remote-site-setup.sh /etc/osg/image-config.d/
COPY 50-nonroot-gratia-setup.sh /etc/osg/image-config.d/

COPY 99-container.conf /usr/share/condor-ce/config.d/

# do the bad thing of overwriting the existing cron job for fetch-crl
ADD fetch-crl /etc/cron.d/fetch-crl
RUN chmod 644 /etc/cron.d/fetch-crl

# HACK: override bosco_cluster so that it doesn't copy over the SSH
# pub key to the remote side. We set this up with the site out of band.
ADD overrides/bosco_cluster /usr/bin/bosco_cluster

# Update Ubuntu 18 to use the latest 1.3 tarball (SOFTWARE-4337)
ADD overrides/bosco_findplatform /usr/bin/bosco_findplatform

# FIXME: override remote_gahp to fix issues with HPC job submission.  This can
# be dropped when https://github.com/htcondor/htcondor/pull/130 is merged and
# released in HTConodr 8.9
ADD overrides/remote_gahp /usr/sbin/remote_gahp

# HACK: override condor_ce_jobmetrics from SOFTWARE-4183 until it is released in
# HTCondor-CE.
ADD overrides/condor_ce_jobmetrics /usr/share/condor-ce/condor_ce_jobmetrics

# Include script to drain the CE and upload accounting data to prepare for container teardown
COPY drain-ce.sh /usr/local/bin/

COPY configure-nonroot-gratia.py /usr/local/bin/

# Use "ssh -q" in bosco_cluster and update-remote-wn-client until the changes have been
# upstreamed to condor and hosted-ce-tools packaging, respectively
COPY overrides/ssh_q.patch /tmp
RUN patch -d / -p0 < /tmp/ssh_q.patch

# FIXME: Squid env var only needs to be readable by workers (SOFTWARE-4362).
# Can be dropped after osg-configure is built into osg-minefield with this patch
COPY overrides/internal-squid.patch /tmp
RUN patch -d /usr/lib/python3.6/site-packages -p1 < /tmp/internal-squid.patch

# Set up Bosco override dir from Git repo (SOFTWARE-3903)
# Expects a Git repo with the following directory structure:
#     RESOURCE_NAME_1/
#         bosco_override/
#         ...
#     RESOURCE_NAME_2/
#         bosco_override/
#         ...
#     ...
COPY bosco-override-setup.sh /usr/local/bin

# FIXME: osg-configure should only warn on fetch-crl failure (SOFTWARE-4364)
COPY overrides/SOFTWARE-4364.crl-warning.patch /tmp
RUN patch -d /usr/lib/python3.6/site-packages -p1 < /tmp/SOFTWARE-4364.crl-warning.patch

# Manage HTCondor-CE with supervisor
COPY 10-htcondor-ce.conf /etc/supervisord.d/

