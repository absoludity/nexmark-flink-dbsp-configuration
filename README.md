# Automated setup for running Nexmark Flink benchmarks

(and comparing the Nexmark/Flink benchmarks with the Database Stream Processor Nexmark benchmarks)

The [playbook](./playbook.yaml) is based on the cluster setup instructions found in the [Nexmark Flink repository](https://github.com/nexmark/nexmark#setup-cluster).

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
./flink/bin/start-cluster.sh && ./nexmark/bin/setup_cluster.sh
```

and run queries with:

```shell
./nexmark/bin/run-query.sh q1
```

To run the full set of queries on a remote machine, it is best to use screen or byobu to ensure that if the connection is interrupted you can reconnect.

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

Then create three `m5ad.4xlarge` instances (64Gb, 16vCPU, 2x300 SSD) with an Ubuntu 20.04 LTS OS, with the keypair created above ready for ssh access. The default image has only 8Gb for the root partition, so update that to use the full 600Gb.

```shell
aws ec2 run-instances --image-id ami-0c1704bac156af62c --count 4 --instance-type m5ad.4xlarge --key-name nexmark-bench --block-device-mappings '{"DeviceName": "/dev/sda1", "Ebs": { "VolumeSize": 600 } }'
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

## DEBUGGING

After identifying and working through a bunch of other issues, I'm able to run the nexmark tests partially, but even though I'm currently running with doubled `taskmanager.memory.process.size` and `jobmanager.memory.process.size` as well updated `numberOfTaskSlots` from 1 to 4 (see flink-conf.yaml). I still see the number of cores dropping at a particular point during *some* queries. For example, q0, q1, q2, q3 and q4 all drop from a high number of reported cores down to 0.02 during their runs. It appears that the earlier this drops, the slower the query will be (as you'd expect), but I've not yet found *why* this is happening:

```shell
$ ./nexmark/bin/run_query.sh
Benchmark Queries: [q0, q1, q2, q3, q4, q5, q7, q8, q9, q10, q11, q12, q13, q14, q15, q16, q17, q18, q19, q20, q21, q22]
==================================================================
Start to run query q0 with workload [tps=10 M, eventsNum=100 M, percentage=bid:46,auction:3,person:1,kafkaServers:null]
Start the warmup for at most 120000ms and 100000000 events.
Stop the warmup, cost 120100ms.
Monitor metrics after 10 seconds.
Start to monitor metrics until job is finished.
Current Cores=8.05 (3 TMs)
Current Cores=8.06 (3 TMs)
Current Cores=8.05 (3 TMs)
Current Cores=8.16 (3 TMs)
Current Cores=8.02 (3 TMs)
Current Cores=8.05 (3 TMs)
Current Cores=8.02 (3 TMs)
Current Cores=8.03 (3 TMs)
Current Cores=8.03 (3 TMs)
Current Cores=8.04 (3 TMs)
Current Cores=5.97 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.04 (3 TMs)
Summary Average: EventsNum=100,000,000, Cores=5.41, Time=89.940 s
Stop job query q0
==================================================================
Start to run query q1 with workload [tps=10 M, eventsNum=100 M, percentage=bid:46,auction:3,person:1,kafkaServers:null]
Start the warmup for at most 120000ms and 100000000 events.
Stop the warmup, cost 120100ms.
Monitor metrics after 10 seconds.
Start to monitor metrics until job is finished.
Current Cores=8.03 (3 TMs)
Current Cores=8.03 (3 TMs)
Current Cores=8.05 (3 TMs)
Current Cores=8.08 (3 TMs)
Current Cores=8.04 (3 TMs)
Current Cores=8.05 (3 TMs)
Current Cores=8.03 (3 TMs)
Current Cores=8.03 (3 TMs)
Current Cores=8.03 (3 TMs)
Current Cores=8.04 (3 TMs)
Current Cores=7.49 (3 TMs)
Current Cores=1.76 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.01 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.02 (3 TMs)
Summary Average: EventsNum=100,000,000, Cores=2.2, Time=211.286 s
Stop job query q1
==================================================================
Start to run query q2 with workload [tps=10 M, eventsNum=100 M, percentage=bid:46,auction:3,person:1,kafkaServers:null]
Start the warmup for at most 120000ms and 100000000 events.
Stop the warmup, cost 63800ms.
Monitor metrics after 10 seconds.
Start to monitor metrics until job is finished.
Current Cores=8.03 (3 TMs)
Current Cores=8.04 (3 TMs)
Current Cores=8.03 (3 TMs)
Current Cores=8.03 (3 TMs)
Current Cores=8.03 (3 TMs)
Current Cores=8.03 (3 TMs)
Current Cores=8.02 (3 TMs)
Current Cores=8.04 (3 TMs)
Current Cores=8.02 (3 TMs)
Current Cores=7.21 (3 TMs)
Current Cores=0.41 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.01 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.01 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.01 (3 TMs)
Current Cores=0.02 (3 TMs)
Summary Average: EventsNum=100,000,000, Cores=2.68, Time=159.545 s
Stop job query q2
==================================================================
Start to run query q3 with workload [tps=10 M, eventsNum=100 M, percentage=bid:46,auction:3,person:1,kafkaServers:null]
Start the warmup for at most 120000ms and 100000000 events.
Stop the warmup, cost 120100ms.
Monitor metrics after 10 seconds.
Start to monitor metrics until job is finished.
Current Cores=8.56 (3 TMs)
Current Cores=8.58 (3 TMs)
Current Cores=8.54 (3 TMs)
Current Cores=8.55 (3 TMs)
Current Cores=8.53 (3 TMs)
Current Cores=8.53 (3 TMs)
Current Cores=8.5 (3 TMs)
Current Cores=8.52 (3 TMs)
Current Cores=8.52 (3 TMs)
Current Cores=8.54 (3 TMs)
Current Cores=8.55 (3 TMs)
Current Cores=8.55 (3 TMs)
Current Cores=8.55 (3 TMs)
Current Cores=8.54 (3 TMs)
Current Cores=6.6 (3 TMs)
Current Cores=1.92 (3 TMs)
Current Cores=0.16 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.02 (3 TMs)
Summary Average: EventsNum=100,000,000, Cores=4.76, Time=145.847 s
Stop job query q3
==================================================================
Start to run query q4 with workload [tps=10 M, eventsNum=100 M, percentage=bid:46,auction:3,person:1,kafkaServers:null]
Start the warmup for at most 120000ms and 100000000 events.
Stop the warmup, cost 120100ms.
Monitor metrics after 10 seconds.
Start to monitor metrics until job is finished.
Current Cores=19 (3 TMs)
Current Cores=18.08 (3 TMs)
Current Cores=15.87 (3 TMs)
Current Cores=15.03 (3 TMs)
Current Cores=15.86 (3 TMs)
Current Cores=14.75 (3 TMs)
Current Cores=14.49 (3 TMs)
Current Cores=14.63 (3 TMs)
Current Cores=15.01 (3 TMs)
Current Cores=13.62 (3 TMs)
Current Cores=13.86 (3 TMs)
Current Cores=15.03 (3 TMs)
Current Cores=15.76 (3 TMs)
Current Cores=14.63 (3 TMs)
Current Cores=13.47 (3 TMs)
Current Cores=15.33 (3 TMs)
Current Cores=14.18 (3 TMs)
Current Cores=13.9 (3 TMs)
Current Cores=13.6 (3 TMs)
Current Cores=14.61 (3 TMs)
Current Cores=13.42 (3 TMs)
Current Cores=12.85 (3 TMs)
Current Cores=13.43 (3 TMs)
Current Cores=13.71 (3 TMs)
Current Cores=12.83 (3 TMs)
Current Cores=12.37 (3 TMs)
Current Cores=12.64 (3 TMs)
Current Cores=16.25 (3 TMs)
Current Cores=14.05 (3 TMs)
Current Cores=14.15 (3 TMs)
Current Cores=13.25 (3 TMs)
Current Cores=13.5 (3 TMs)
Current Cores=13.25 (3 TMs)
Current Cores=12.63 (3 TMs)
Current Cores=13.34 (3 TMs)
Current Cores=8.88 (3 TMs)
Current Cores=7.35 (3 TMs)
Current Cores=12.92 (3 TMs)
Current Cores=13.45 (3 TMs)
Current Cores=13.01 (3 TMs)
Current Cores=12.9 (3 TMs)
Current Cores=13.85 (3 TMs)
Current Cores=12.47 (3 TMs)
Current Cores=12.29 (3 TMs)
Current Cores=12.35 (3 TMs)
Current Cores=13.33 (3 TMs)
Current Cores=15.36 (3 TMs)
Current Cores=13.49 (3 TMs)
Current Cores=13.92 (3 TMs)
Current Cores=13.85 (3 TMs)
Current Cores=13.68 (3 TMs)
Current Cores=14.32 (3 TMs)
Current Cores=12.31 (3 TMs)
Current Cores=11.62 (3 TMs)
Current Cores=12.99 (3 TMs)
Current Cores=12.27 (3 TMs)
Current Cores=13.23 (3 TMs)
Current Cores=12.13 (3 TMs)
Current Cores=11.71 (3 TMs)
Current Cores=12.56 (3 TMs)
Current Cores=12.48 (3 TMs)
Current Cores=13.29 (3 TMs)
Current Cores=12.53 (3 TMs)
Current Cores=11.98 (3 TMs)
Current Cores=12.65 (3 TMs)
Current Cores=12.16 (3 TMs)
Current Cores=15.85 (3 TMs)
Current Cores=14.98 (3 TMs)
Current Cores=14.16 (3 TMs)
Current Cores=13.55 (3 TMs)
Current Cores=12.95 (3 TMs)
Current Cores=11.08 (3 TMs)
Current Cores=5.73 (3 TMs)
Current Cores=8.12 (3 TMs)
Current Cores=8.91 (3 TMs)
Current Cores=5.3 (3 TMs)
Current Cores=0.89 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.03 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Current Cores=0.02 (3 TMs)
Summary Average: EventsNum=100,000,000, Cores=9.4, Time=541.751 s
Stop job query q4
==================================================================

```

Only clues I can find in logs don't yet help me find what needs to change.

This first one, a failed checkpoint, looks like a result of the issue (the task is no longer running):

```shell
2022-09-27 01:34:26,568 INFO  org.apache.flink.runtime.checkpoint.CheckpointFailureManager [] - Failed to trigger checkpoint for job 741279a6d3195b7d34a8e7dfc881b51f since Checkpoint triggering task Source: datagen[1] -> Calc[2] -> WatermarkAssigner[3] -> Calc[4] -> Sink: discard_sink[5] (4/8) of job 741279a6d3195b7d34a8e7dfc881b51f is not being executed at the moment. Aborting checkpoint. Failure reason: Not all required tasks are currently running..
```

Occasional metric failures don't seem relevant (but I don't know their cause either):

```shell
2022-09-27 02:13:54,678 WARN  com.github.nexmark.flink.metric.MetricReporter               [
] - Job metric is not ready yet.
java.lang.RuntimeException: Can't find TPS metric name from the response:
[]
        at com.github.nexmark.flink.metric.FlinkRestClient.getTpsMetricName(FlinkRestClient.
java:165) ~[nexmark-flink-0.2-SNAPSHOT.jar:?]
        at com.github.nexmark.flink.metric.MetricReporter.getJobInformation(MetricReporter.j
ava:96) [nexmark-flink-0.2-SNAPSHOT.jar:?]
        at com.github.nexmark.flink.metric.MetricReporter.submitMonitorThread(MetricReporter
.java:70) [nexmark-flink-0.2-SNAPSHOT.jar:?]
        at com.github.nexmark.flink.metric.MetricReporter.reportMetric(MetricReporter.java:1
40) [nexmark-flink-0.2-SNAPSHOT.jar:?]
        at com.github.nexmark.flink.QueryRunner.run(QueryRunner.java:85) [nexmark-flink-0.2-
SNAPSHOT.jar:?]
        at com.github.nexmark.flink.Benchmark.executeQueries(Benchmark.java:202) [nexmark-fl
ink-0.2-SNAPSHOT.jar:?]
        at com.github.nexmark.flink.Benchmark.runQueries(Benchmark.java:109) [nexmark-flink-
0.2-SNAPSHOT.jar:?]
        at com.github.nexmark.flink.Benchmark.main(Benchmark.java:81) [nexmark-flink-0.2-SNA
PSHOT.jar:?]
```

The most relevant failure that I see occasionally is this unable to fulfil resource requirements:

```shell
2022-09-27 05:32:36,466 INFO  org.apache.flink.runtime.resourcemanager.slotmanager.DeclarativeSlotManager [] - Received resource requirements from job 045c630d3f4ef49bcdde0c0dc4a34781: [ResourceRequirement{resourceProfile=ResourceProfile{UNKNOWN}, numberOfRequiredSlots=4}]
2022-09-27 05:32:36,467 WARN  org.apache.flink.runtime.resourcemanager.slotmanager.DeclarativeSlotManager [] - Could not fulfill resource requirements of job 045c630d3f4ef49bcdde0c0dc4a34781. Free slots: 0
2022-09-27 05:32:36,467 WARN  org.apache.flink.runtime.jobmaster.slotpool.DeclarativeSlotPoolBridge [] - Could not acquire the minimum required resources, failing slot requests. Acquired: [ResourceRequirement{resourceProfile=ResourceProfile{cpuCores=1, taskHeapMemory=3.225gb (3462817321 bytes), taskOffHeapMemory=0 bytes, managedMemory=2.780gb (2985002310 bytes), networkMemory=711.680mb (746250577 bytes)}, numberOfRequiredSlots=3}]. Current slot pool status: Registered TMs: 3, registered slots: 3 free slots: 0
```

But I've upped the size of the instances, so they have 64Gb ram, 600Gb SSD, 16vCPUs, and have also updated the flink configuration as mentioned above.

At a bit of a loss to identify more. Killed instances after 4th query due to the above.
