Step 1 - on ALL nodes

	1. Add IP and hostname in /etc/hosts
	2. Set hostnames on nodes
		hostnamectl set-hostname mysqlsrv1
		hostnamectl set-hostname mysqlsrv2
		
Step 2 - on ALL nodes

	1. Set SElinux to permissive mode
		
		nano /etc/selinux/config
		
	2. Install Pacemaker and Corosync
		
		yum install -y pcs
		
	3. Install management for Selinux
		
		yum install -y policycoreutils-python
		
	4. In RHEL 7, we have to set up a password for the pcs administration account named hacluster
		
		echo "passwd" | passwd hacluster --stdin
		
	5. Start and enable the service
	
		systemctl start pcsd.service 
		systemctl enable pcsd.service

Step 3 - Config Corosync

	1. Authenticate as the hacluster user. Authorization tokens are stored in the file /var/lib/pcsd/tokens
	
		a. [mysqlsrv1]# pcs cluster auth mysqlsrv1 mysqlsrv2 -u hacluster -p passwd
		
	2. Generate and synchronize the Corosync configuration.
	
		a. [mysqlsrv1]# pcs cluster setup --name mysql_cluster mysqlsrv1 mysqlsrv2
		
	3. Start the cluster on all nodes
	
		a. [mysqlsrv1]# pcs cluster start --all
	
Step 4 - Install DRBD - on ALL nodes

	1. DRBD Installation
	
		a. rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
		b. rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-2.el7.elrepo.noarch.rpm
		c. yum install -y kmod-drbd84 drbd84-utils
		
	2. To avoid issues with SELinux, for the time being, we are going to exempt DRBD processes from SELinux control
	
		a. semanage permissive -a drbd_t
		
	3. Configure DRBD
	
		nano /etc/drbd.d/mysql01.res
		resource mysql01 {
		 protocol C;
		 meta-disk internal;
		 device /dev/drbd0;
		 disk   /dev/sdb1;
		 handlers {
		  split-brain "/usr/lib/drbd/notify-split-brain.sh root";
		 }
		 net {
		  allow-two-primaries no;
		  after-sb-0pri discard-zero-changes;
		  after-sb-1pri discard-secondary;
		  after-sb-2pri disconnect;
		  rr-conflict disconnect;
		 }
		 disk {
		  on-io-error detach;
		 }
		 syncer {
		  verify-alg sha1;
		 }
		 on mysqlsrv1 {
		  address  [ipnode1]:7789;
		 }
		 on mysqlsrv2 {
		  address  [ipnode2]:7789;
		 }
		}
		
	1. Create the local metadata for the DRBD resource
	
		a. drbdadm create-md mysql01
		
	2. Ensuring that a DRBD kernel module is loaded, bring up the DRBD resource
	
		a. drbdadm up mysql01
		
	3. For data consistency, tell DRBD which node should be considered to have the correct data (can be run on any node as both have garbage at this point)
	
		a. [mysqlsrv1 ]# drbdadm primary --force mysql01
		
	4. Observe the sync
	
		a. [mysqlsrv1]# cat /proc/drbd
		
	5. Create a filesystem on the DRBD device and tune as required
	
		a. [mysqlsrv1 ]# mkfs.ext4 -m 0 -L drbd /dev/drbd0
		b. [mysqlsrv1 ]# tune2fs -c 30 -i 180d /dev/drbd0
		
	6. Mount the disk, we will populate it with MySQL content shortly
	
		a. [mysqlsrv1 ]# mount /dev/drbd0 /mnt
	
Step 5 - Install MySQL

	1. MySQL Installation
	
		a. yum -y install https://dev.mysql.com/get/mysql80-community-release-el7-1.noarch.rpm
		b. sudo yum install -y mysql-community-server
		
	2. Ensure the MySQL service is disabled, as it will managed by pacemaker
	
		a. systemctl disable mysqld.service
		
	3. Now start the MySQL service manually on one of the cluster nodes
	
		a. [mysqlsrv1]# systemctl start mysqld.service
		
	4. We need to give the same SELinux policy as the MySQL DB datadir. The mysqld policy stores data with multiple different file context types under the /var/lib/mysql directory. If we want to store the data in a different directory, we can use the semanage command to add file context
	
		a. [mysqlsrv1]# semanage fcontext -a -t mysqld_db_t "/mnt(/.*)?"
		b. [mysqlsrv1]# restorecon -Rv /mnt
		
	5. At this point our preparation is complete, we can unmount the temporarily mounted filesystem and stop the MySQL DB service
	
		a. [mysqlsrv1]# umount /mnt
		b. [mysqlsrv1]# systemctl stop mysqld.service
		
	6. Last thing to do, we have to put some very basic my.cnf configuration
	
		a. nano /etc/my.cnf
		symbolic-links=0
		bind_address = *
		require_secure_transport = ON
		!includedir /etc/my.cnf.d
	
Step 6 - Configure Pacemaker Cluster

	1. We want the configuration logic and ordering to be as below:
	
		Start: mysql_fs01 ; mysql_VIP01
		Stop: mysql_VIP01 ; mysql_fs01.
		
	2. One handy feature pcs has is the ability to queue up several changes into a file and commit those changes atomically. To do this, we start by populating the file with the current raw XML config from the CIB
	
		a. [mysqlsrv1]# pcs cluster cib clust_cfg
		
	3. Disable STONITH. Be advised that a node level fencing configuration depends heavily on environment.
	
		a. [mysqlsrv1]# pcs -f clust_cfg property set stonith-enabled=false
		
	4. Set quorum policy to ignore
	
		a. [mysqlsrv1]# pcs -f clust_cfg property set no-quorum-policy=ignore
		
	5. Prevent the resources from moving after recovery as it usually increases downtime
	
		a. [mysqlsrv1]# pcs -f clust_cfg resource defaults resource-stickiness=200
		
	6. Create a cluster resource named mysql_data01 for the DRBD device, and an additional clone resource MySQLClone01 to allow the resource to run on both cluster nodes at the same time
	
		[mysqlsrv1]# pcs -f clust_cfg resource create mysql_data01 ocf:linbit:drbd drbd_resource=mysql01 op monitor interval=30s
		[mysqlsrv1]# pcs -f clust_cfg resource master MySQLClone01 mysql_data01 master-max=1 master-node-max=1 clone-max=2 clone-node-max=1 notify=true
		
	7. Create a cluster resource named mysql_fs01 for the filesystem. Tell the cluster that the clone resource MySQLClone01 must be run on the same node as the filesystem resource, and that the clone resource must be started before the filesystem resource
	
		[mysqlsrv1]# pcs -f clust_cfg resource create mysql_fs01 Filesystem device="/dev/drbd0" directory="/var/lib/mysql" fstype="ext4"
		[mysqlsrv1]# pcs -f clust_cfg constraint colocation add mysql_fs01 with MySQLClone01 INFINITY with-rsc-role=Master
		[mysqlsrv1]# pcs -f clust_cfg constraint order promote MySQLClone01 then start mysql_fs01
		
	8. Finally, create a cluster resource named mysql_VIP01 for the virtual IP HAproxyIP.
	
		[mysqlsrv1]# pcs -f clust_cfg resource create mysql_VIP01 ocf:heartbeat:IPaddr2 ip=192.168.31.200 cidr_netmask=32 op monitor interval=30s
		
	9. The virtual IP mysql_VIP01 resource must be run on the same node as the MySQL DB resource, naturally, and must be started the last. This is to ensure that all other resources are already started before we can connect to the virtual IP
	
		a. [mysqlsrv1]# pcs -f clust_cfg constraint colocation add mysql_VIP01 with mysql_service01 INFINITY
		b. [mysqlsrv1]# pcs -f clust_cfg constraint order mysql_service01 then mysql_VIP01
		
	10. Let us check the configuration
	
		[mysqlsrv1]# pcs -f clust_cfg constraint
			Location Constraints:
			Ordering Constraints:
			  promote MySQLClone01 then start mysql_fs01 (kind:Mandatory)
			  start mysql_fs01 then start mysql_service01 (kind:Mandatory)
			  start mysql_service01 then start mysql_VIP01 (kind:Mandatory)
			Colocation Constraints:
			  mysql_fs01 with MySQLClone01 (score:INFINITY) (with-rsc-role:Master)
			  mysql_service01 with mysql_fs01 (score:INFINITY)
			  mysql_VIP01 with mysql_service01 (score:INFINITY)</pre>
		[mysqlsrv1]# pcs -f clust_cfg resource show
			 Master/Slave Set: MySQLClone01 [mysql_data01]
			     Stopped: [ mysqlsrv1-cr mysqlsrv2-cr ]
			 mysql_fs01	(ocf::heartbeat:Filesystem):	Stopped
			 mysql_service01	(ocf::heartbeat:mysql):	Stopped
			 mysql_VIP01	(ocf::heartbeat:IPaddr2):	Stopped
			 
	11. We can commit changes now and check cluster status
	
		a. [mysqlsrv1]# pcs cluster cib-push clust_cfg
		b. [mysqlsrv1]# pcs status

Configure HAProxy
On the server that has HAProxy installed, edit the configuration file at /etc/haproxy/haproxy.cfg to contain the following
	
	global
	maxconn 100
	defaults
	log global
	mode tcp
	retries 2
	timeout client 30m
	timeout connect 4s
	timeout server 30m
	timeout check 5s
	
	listen stats
	mode http
	bind *:7000
	stats enable
	stats uri /
	
	listen mysql
	bind *:5000
	option httpchk
	http-check expect status 200
	default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
	server mysqlsrv1 [ipnode1]:3306 maxconn 100 check port 3306
	server mysqlsrv2 [ipnode2]:3306 maxconn 100 check port 3306
