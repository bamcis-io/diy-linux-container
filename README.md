# diy-linux-container
A proof of concept for building a container from scratch.

## Instructions
Copy this script onto a linux host (assuming Amazon Linux 2). Make it executable with `chmod +x <filename>`. Make sure your host has internet access. Run the script and review the output. It will create a 1 GB btrfs volume to host the container image, please make sure you have at least 1 GB available on your host volume.

## Details
The script installs docker and uses the docker bridge for network connectivity as well as uses it to download an alpine linux file system. However, it doesn't use docker to actually run any of the container components. It assumes a docker network of 172.17.0.0/16, if your docker setup uses a different network, you'll need to update the IP addresses used.

The script creates a network namespace, then uses `unshare` to launch a new process in its own namespace. You'll be able to view the effects of this via the containers view of `PID`, the mount namespace, and the `UTS` namespace (via hostname). 

While the script sets up cgroups, it doesn't really demonstrate how they're used. It also doesn't include setting up features like seccomp. The point of this is to get a basic understanding of how linux namespaces power modern container technology to create isolation. 
