################################################################
#
# Amazon EC2 PostGIS 1.4 on RAID-x n-disk EBS Array Build Script
# 
# Complete Rip off of:
# http://alestic.com/2009/06/ec2-ebs-raid
# http://biodivertido.blogspot.com/2009/10/install-postgresql-84-and-postgis-140.html
#
# Additional glue by Simon Tokumine, 15/11/09
#
# INSTALL ON ALESTIC UBUNTU JAUNTY AMI'S - http://alestic.com/
# I USED THE 32-bit AMI: ami-ccf615a5
#
# NOTE, THIS IS ONLY FOR TESTING
################################################################

################################################################
#SETUP
#Please complete the parts that are in []'s (over writing the []'s)
#then just run the script on the server
################################################################ 
export EC2_PRIVATE_KEY=/root/pk.pem #[THE_LOCATION_ON_SERVER_OF_YOUR_X509_PRIVATE_KEY]
export EC2_CERT=/root/cert.pem #[THE_LOCATION_ON_SERVER_OF_YOUR_X509_PUBLIC_KEY]
instanceid=[i-2b006643 - the amazon EC2 instance id] 
availability_zone = [us-east-1d]
volumes=[10 - the number of EBS volumes you want to run your array over. Limit of 20 unless you've asked amazon]
size=[5 - the size of each EBS volume in GB]
mountpoint=[/vol]
raid_array_location=[/dev/md0]
raid_level=[0]
postgres_password=[atlas]
db_name=[geodb]
################################################################

#####
# TODO
#
# UNMOUNT AND DETACH/DESTROY EBS & TERMINATE EC2
# 
#####


################################################################
# CREATE EBS VOLUMES & RAID ARRAY
################################################################
apt-get update
apt-get -y install ec2-api-tools
apt-get -y install sun-java6-bin
export JAVA_HOME=/usr/lib/jvm/java-6-sun

devices=$(perl -e 'for$i("h".."k"){for$j("",1..15){print"/dev/sd$i$j\n"}}'|
           head -$volumes)
devicearray=($devices)
volumeids=
i=1
while [ $i -le $volumes ]; do
  volumeid=$(ec2-create-volume -z $availability_zone --size $size | cut -f2)
  echo "$i: created  $volumeid"
  device=${devicearray[$(($i-1))]}
	echo $volumeid
  ec2-attach-volume $volumeid -i $instanceid -d $device 
  volumeids="$volumeids $volumeid"
  let i=i+1
done
echo "volumeids='$volumeids'"

sudo apt-get update &&
sudo apt-get install -y mdadm xfsprogs

devices=$(perl -e 'for$i("h".."k"){for$j("",1..15){print"/dev/sd$i$j\n"}}'|
           head -$volumes)

yes | sudo mdadm          \
  --create $raid_array_location       \
  --level $raid_level              	 	\
  --metadata=1.1          \
  --raid-devices $volumes \
  $devices

echo DEVICE $devices       | sudo tee    /etc/mdadm.conf
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm.conf

sudo mkfs.xfs $raid_array_location

echo "$raid_array_location $mountpoint xfs noatime 0 0" | sudo tee -a /etc/fstab
sudo mkdir $mountpoint
sudo mount $mountpoint

################################################################
# INSTALL POSTGRES, POSTGIS & SETUP DATABASE ON RAID VOLUME 
################################################################
echo " " >> /etc/apt/sources.list
echo "deb http://ppa.launchpad.net/pitti/postgresql/ubuntu jaunty main" >> /etc/apt/sources.list
echo "deb-src http://ppa.launchpad.net/pitti/postgresql/ubuntu jaunty main" >> /etc/apt/sources.list
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 8683D8A2
sudo apt-get update
sudo apt-get -y install postgresql-8.4 postgresql-server-dev-8.4 libpq-dev libgeos-dev proj
sudo /etc/init.d/postgresql-8.4 stop
mkdir $mountpoint/data
chown postgres $mountpoint/data
sudo -u postgres /usr/lib/postgresql/8.4/bin/initdb -D $mountpoint/data
sudo sed -i.bak -e 's/port = 5433/port = 5432/' /etc/postgresql/8.4/main/postgresql.conf
sudo sed -i.bak -e "s@\/var\/lib\/postgresql\/8.4\/main@$mountpoint\/data@" /etc/postgresql/8.4/main/postgresql.conf
sudo sed -i.bak -e 's/ssl = true/#ssl = true/' /etc/postgresql/8.4/main/postgresql.conf
sudo /etc/init.d/postgresql-8.4 start
cd /tmp
# install postgis as a package for easier removal if needed
wget http://postgis.refractions.net/download/postgis-1.4.0.tar.gz
tar xvfz postgis-1.4.0.tar.gz
cd postgis-1.4.0
./configure
make && sudo checkinstall --pkgname postgis --pkgversion 1.4-src --default
sudo -u postgres psql -c"ALTER user postgres WITH PASSWORD '$postgres_password'"
sudo -u postgres createdb $db_name   
sudo -u postgres createlang -d$db_name plpgsql
sudo -u postgres psql -d$db_name -f /usr/share/postgresql/8.4/contrib/postgis.sql
sudo -u postgres psql -d$db_name -f /usr/share/postgresql/8.4/contrib/spatial_ref_sys.sql
sudo -u postgres psql -d$db_name -c"select postgis_lib_version();"
