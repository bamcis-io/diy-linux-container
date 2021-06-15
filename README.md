# diy-linux-container
A proof of concept for building a container from scratch.

## Instructions
Copy this script onto a linux host (assuming Amazon Linux 2). Make it executable with `chmod +x <filename>`. Make sure your host has internet access. Run the script and review the output. It will create a 1 GB btrfs volume to host the container image, please make sure you have at least 1 GB available on your host volume.

## Details
The script installs docker and uses it to download an alpine linux file system. However, it doesn't use docker to actually run any of the container components. By default the script uses `iptables` to set up NAT for internet connectivity. You can alternatively use the `create_net_ns_with_docker` function to set up networking using the `docker0` bridge (and expects the docker network to be 172.17.0.0/16).

The script creates a network namespace, then uses `unshare` to launch a new process in its own namespace. You'll be able to view the effects of this via the containers view of `PID`, the mount namespace, and the `UTS` namespace (via hostname). 

While the script sets up cgroups, it doesn't really demonstrate how they're used. It also doesn't include setting up features like seccomp. The point of this is to get a basic understanding of how linux namespaces power modern container technology to create isolation.

## References
I used these sites to help build the full working demo.

https://blog.nicolasmesa.co/posts/2018/08/container-creation-using-namespaces-and-bash/
https://josephmuia.ca/2018-05-16-net-namespaces-veth-nat/
https://www.youtube.com/watch?v=sK5i-N34im8
https://stackoverflow.com/questions/42805494/run-multiple-commands-in-network-namespace
