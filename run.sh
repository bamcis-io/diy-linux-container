#!/bin/bash

CID=""
PID=""

install_docker() {
    sudo yum install docker -y &> /dev/null
    [ $(getent group docker) ] || sudo groupadd docker # create the group in case it wasn't created during docker install
    sudo gpasswd -a $USER docker
    sudo systemctl enable docker.service
    sudo systemctl enable containerd.service
    sudo systemctl start docker.service
}

create_btrfs_volume() {
    echo "Creating btrfs volume"
    # setup btrfs, a copy on write file system
    sudo yum install btrfs-progs -y &> /dev/null # install btrfs tools
    sudo dd if=/dev/zero of=disk.img bs=512 count=2097152 # Makes a 1GB disk image
    sudo mkfs.btrfs disk.img # format the disk image with btrfs
    sudo mkdir -p $1 # create the dir to host the mount
    sudo mount -t btrfs ~/disk.img $1 # mount the disk image to the directory
}

build_container_image() {
    # setup a new empty directory for this
    sudo mkdir -p images
    sudo mkdir -p containers
    # make mounts private so they aren't exposed to the host from the container
    sudo mount --make-rprivate /

    # download an image 
    sudo btrfs subvol create images/alpine # create a btrfs subvolume
    CID=$(docker run -d alpine true) # gets the container id, doesn't leave it running
    echo "Container id $CID"
    mkdir -p images/alpine
    docker export $CID | sudo tar -C images/alpine/ -xf- # export the file system to a folder
    sudo btrfs subvol snapshot images/alpine containers/tupperware # snapshot the image to the directory
    sudo touch containers/tupperware/THIS_IS_TUPPERWARE # just an indicator so we know what file system we're looking at
    sudo chown -R ${USER}: /btrfs # allow current user to own the directory
}

setup_cgroups() {
    # create cgroups for mem and cpu
    sudo mkdir -p /sys/fs/cgroup/memory/tupperware
    sudo mkdir -p /sys/fs/cgroup/cpu/tupperware

    # set 100MB memory limit
    #echo 100M > /sys/fs/cgroup/memory/tupperware/memory.limit_in_bytes
    
    # disable swap
    #echo "0" > /sys/fs/cgroup/memory/tupperware/memory.swappiness
}

environment_setup() {
    install_docker
    sudo touch /I_AM_THE_HOST
    create_btrfs_volume /btrfs
    cd /btrfs
    build_container_image
    setup_cgroups
}

environment_cleanup() {
    echo "Removing container $1"
    echo "Killing process $2"
    kill $2 || "no process to kill"
    sudo umount -l /btrfs
    rm -f ~/disk.img
    docker rm $1 &> /dev/null
    sudo systemctl stop docker &> /dev/null
    sudo ip netns delete "netns1" || echo ""
    sudo ip link delete hnetns1 || echo ""
    exit
}

change_rootfs() {
    cd $1
    mkdir /btrfs/containers/tupperware/oldroot
    sudo mount --bind /btrfs/containers/tupperware/ /btrfs
    cd /btrfs
    sudo pivot_root . oldroot/
    cd /
    mount -t proc proc /proc
    umount --all
    mount -t proc proc /proc
    umount -l /oldroot # detach the filesystem from the file hierarchy now, and clean up all references to this filesystem as soon as it is not busy anymore
}

enter_container() {
 
    sudo ip netns exec $1 unshare --mount --uts --ipc --pid --fork /bin/sh -c "
    
    mkdir /btrfs/containers/tupperware/oldroot
    mount --bind /btrfs/containers/tupperware/ /btrfs 
    cd /btrfs
    pivot_root . oldroot/
    cd /
    mount -t proc proc /proc
    umount -a &> /dev/null
    mount -t proc proc /proc
    umount -l /oldroot
    
    # add the rng devices for apache to use
    mknod -m 444 /dev/random c 1 8
    mknod -m 444 /dev/urandom c 1 9

    # Change the hostname in the container
    hostname tupperware

    # Configure DNS
    echo nameserver 8.8.8.8 > /etc/resolv.conf

    # install apache
    apk add apache2 --no-cache &> /dev/null

    # turn on cgi
    sed -i -e '/index\.html$/s/$/ index.sh index.cgi/' \
       -e '/LoadModule cgi/s/#//' \
       -e '/Scriptsock cgisock/s/#//' \
       -e '/AddHandler cgi-script .cgi/s/#//' \
       -e '/AddHandler cgi-script .cgi/s/$/ .sh .py/' \
       -e '/Options Indexes FollowSymLinks/s/$/ ExecCGI/' \
       -e 's/LogLevel warn/LogLevel debug/g' \
       -e 's/Options None/Options +ExecCGI/g' /etc/apache2/httpd.conf

    # cgi script to display internal view of container
    echo -e \"#!/bin/sh
    echo \\\"Content-type: text/html\\\"
    echo \\\"\\\"
    echo '<html>'
    echo '<body>'
    echo '<div>'
    echo '<h2>Hostname</h2>'
    echo '<div>'
    hostname
    echo '</div>'
    echo '</div>'
    echo '<div>'
    echo '<h2>Processes</h2>'
    echo '<div>'
    ps
    echo '</div>'
    echo '</div>'
    echo '<div>'
    echo '<h2>File System</h2>'
    echo '<div>'
    ls /
    echo '</div>'
    echo '</div>'
    echo '</body>'
    echo '</html>'
    exit 0\" > /var/www/localhost/cgi-bin/ps-cgi

    chmod +x /var/www/localhost/cgi-bin/ps-cgi
    chown root: /var/www/localhost/cgi-bin/ps-cgi

    # start apache manually
    exec /usr/sbin/httpd -D FOREGROUND -f /etc/apache2/httpd.conf" &

    # process id of last background process launched
    PID=$!
}

create_net_ns() {
    # 1/ add new network namespace
    # 2/ set local loopback to up
    # 3/ ping localhost
    # 4/ create a veth pair on host
    # 5/ move veth to new net namespace
    # 6/ assign IP to host veth
    # 7/ assign IP to container veth
    # 8/ join host to docker and bring up
    # 9/ add default route in container
    # 10/ ping container from host
    # 11/ ping host from container

    NS=""

    if [ $? -lt 2 ] 
    then
        NS="netns1"
        sudo ip netns add $NS # create new network namespace
    else
        NS=$1 # otherwise it's already created and the name was provided
    fi

    IP=$(ip -4 addr show docker0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
 
    sudo ip netns exec $NS ip link set lo up # 2/ bring up loopback in container namespace
    #sudo ip netns exec $NS ping -c 2 localhost # 3/ ping localhost

    sudo ip link add name h$NS type veth peer name c$NS # 4/ create host and container virtual interfaces
    sudo ip link set c$NS netns $NS # 5/ move the virtual device to the new namespace

    sudo ifconfig h$NS 172.17.0.2/16 up # 6/ assign host IP to virtual device
    sudo ip netns exec $NS ifconfig c$NS 172.17.0.3/16 up # 7/ assign container IP to virtual device

    sudo ip link set h$NS master docker0 up # 8/ join host interface to docker bridge
    sudo ip netns exec $NS ip route add default via $IP # 9/ add default route in container

    #ping -c 2 172.17.0.2 # 10/ ping container from host
    #sudo ip netns exec $NS ping -c 2 172.17.0.3 # 11/ ping host from container
    #sudo ip netns exec $NS ping -c 4 8.8.8.8 # 12/ ping the internet
}

# First setup the host environment
echo "Setting up environment"
environment_setup &> /dev/null

# Do the real container stuff here
echo "Finished environment setup"
echo "Building networking namespace"
create_net_ns &> /dev/null

echo "Starting container"
enter_container "netns1" &> /dev/null

# Capture ctrl+c to inject cleanup
trap "environment_cleanup $CID $PID" SIGINT SIGTERM

sleep 5

# Display the host and container views
echo "Original hostname: $(hostname)"
echo ""
echo "Host file system:"
ls /
echo ""
echo "Host process view:"
ps
echo ""
echo "Container view of hostname, ps, and ls:"
curl http://172.17.0.3/cgi-bin/ps-cgi

echo ""
echo "Press ctrl+c to quit this script and stop the container"
echo ""

# wait for ctrl+c
while true
do
    sleep 5
done
