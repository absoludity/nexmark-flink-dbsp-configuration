# Automated setup for running Nexmark Flink benchmarks

(and comparing the Nexmark/Flink benchmarks with the Database Stream Processor Nexmark benchmarks)

## Install Ansible and dependencies

The `community.crypto` collection is needed to generate an ssh key for the Flink leader to communicate with the workers. The `ansible.posix` collection is used to add the public key of the leader to the workers' `authorized_keys`.

```shell
sudo apt install -y ansible
ansible-galaxy collection install community.crypto ansible.posix
```

## Configuring Ansible with your Flink machines

Copy the inventory template:

```shell
cp inventory_temeplate.ini inventory.ini
```

and edit the IP addresses to match the machines you have ready for the roles of your Flink leader and workers, ensuring the `ansible_user` is also correctly set (and potentially the `ansible_ssh_private_key` attribute for ec2 - see appendix below).

Once set, you can run the following to ensure ansible can connect to your machines:

```shell
$ ansible -i inventory.ini all -m ping
10.147.199.20 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
10.147.199.24 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
10.147.199.150 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
```

If you see "authenticity of host can't be established" errors, first let `ssh` know that you trust the host by ssh-ing to that IP address and trusting the host.

## Running the playbook to setup the Nexmark-Flink cluster

Note: This playbook assumes your machines are Ubuntu 20.04 instances.

```shell
ansible-playbook -i inventory.ini playbook.yaml
```

## Running the benchmark

Once the Nexmark-Flink cluster is configured, we can `ssh` to the leader and start the cluster (not automated yet, as requires accepting host authenticity of workers on leader):

```shell
ssh ubuntu@10.147.199.70
./flink/bin/start-cluster.sh
./nexmark/bin/setup-cluster.sh
```

and run queries with:

```shell
./nexmark/bin/run-query.sh q1
```

## Appendix 1: Setting up ec2 instances for running benchmarks

To create your leader and worker instances, first create an ssh key-pair for use with the benchmarking instances:

```shell
aws ec2 create-key-pair \
    --key-name nexmark-bench \
    --key-type rsa \
    --key-format pem \
    --query "KeyMaterial" \
    --output text > $HOME/.ssh/nexmark-bench.pem
chmod 400 $HOME/.ssh/nexmark-bench.pem
```

Then create three `c4.large` instances with an Ubuntu 20.04 LTS OS, with the keypair created above ready for ssh access:

```shell
aws ec2 run-instances --image-id ami-0c1704bac156af62c --count 3 --instance-type c4.large --key-name nexmark-bench
```

Explicitly enable your computer (the ansible host) ssh access to the instances, as well as enabling your leader IP address ssh access:

```shell
aws ec2 authorize-security-group-ingress --group-id sg-0ef693a5bacbce0e1 --protocol tcp --port 22 --cidr x.x.x.x/32
aws ec2 authorize-security-group-ingress --group-id sg-0ef693a5bacbce0e1 --protocol tcp --port 22 --cidr x.x.x.x/32
```

Finally, describe the instances to get the IP addresses for the ansible hosts file, choosing one as the leader.

Note that you'll need to specify the key when using ssh with:

```shell
ssh -i ~/.ssh/nexmark-bench.pem ubuntu@x.x.x.x
```

as well as in the ansible inventory file, for example:

```ini
leader ansible_host=x.x.x.x ansible_user=ubuntu ansible_ssh_private_key_file=/home/username/.ssh/nexmark-bench.pem
...
```

**TODO**: Currently nexmark `run_query.sh` fails when run in this setup as the metrics can't open a socket. Need to update the security group to allow this:

```shell
Exception in thread "main" java.lang.RuntimeException: Could not open socket to receive back cpu metrics.
        at com.github.nexmark.flink.metric.cpu.CpuMetricReceiver.<init>(CpuMetricReceiver.java:63)
        at com.github.nexmark.flink.Benchmark.runQueries(Benchmark.java:98)
        at com.github.nexmark.flink.Benchmark.main(Benchmark.java:81)
Caused by: java.net.UnknownHostException: leader: Temporary failure in name resolution
        at java.net.Inet6AddressImpl.lookupAllHostAddr(Native Method)
        at java.net.InetAddress$2.lookupAllHostAddr(InetAddress.java:929)
        at java.net.InetAddress.getAddressesFromNameService(InetAddress.java:1330)
        at java.net.InetAddress.getAllByName0(InetAddress.java:1283)
        at java.net.InetAddress.getAllByName(InetAddress.java:1199)
        at java.net.InetAddress.getAllByName(InetAddress.java:1127)
        at java.net.InetAddress.getByName(InetAddress.java:1077)
        at com.github.nexmark.flink.metric.cpu.CpuMetricReceiver.<init>(CpuMetricReceiver.java:60)
```

## Appendix 2: Setting up local VMs for testing the nexmark setup

To test the Nexmark Flink benchmark locally on an Ubuntu machine, you can [install multipass](https://multipass.run/install) and run 3 Ubuntu VMs configured with your public SSH key, with:

```shell
for VM in nexmark-leader nexmark-worker1 nexmark-worker2
do
    multipass launch 20.04 --name ${VM} --cpus 2 --mem 2G
    cat ~/.ssh/id_rsa.pub | multipass transfer - ${VM}:/tmp/host_id_rsa.pub
    multipass exec ${VM} -- sh -c 'cat /tmp/host_id_rsa.pub >> /home/ubuntu/.ssh/authorized_keys'
done
```

This should leave you with three VMs, each with their own IP address:

```shell
$ multipass list
Name                    State             IPv4             Image
nexmark-leader          Running           10.147.199.36    Ubuntu 22.04 LTS
nexmark-worker1         Running           10.147.199.193   Ubuntu 22.04 LTS
nexmark-worker2         Running           10.147.199.72    Ubuntu 22.04 LTS
```

Verify that you can `ssh ubuntu@...` for each and you're ready to go.

When you are later finished and want to remove the VMs:

```shell
for VM in nexmark-leader nexmark-worker1 nexmark-worker2
do
    multipass delete ${VM}
done
multipass purge
```
