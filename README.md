# sidecar-container-example

This repository contains the code necessary to test the "new" sidecar-container feature introduced in Kubernetes 1.28 (alpha) and Kubernetes 1.29 (beta, enabled by default).

## Introduction

The idea of this very basic demo is to test the race condition between an app and a utility sidecar (for a database connection for example) in order to run properly.

Here is an example with someone who had the exact same issue than a friend of mine with cloud-sql sidecar (*funny* coincidence).

* [hwchiu.medium.com/exploring-kubernetes-1-28-sidecar-container-support-ed1a39ac7fe0](https://hwchiu.medium.com/exploring-kubernetes-1-28-sidecar-container-support-ed1a39ac7fe0)

This example uses 2 docker images only built for amd64 architectures. If you run on arm64 nodes (or windows nodes LOL), it will fail. See the images files in the repository:

* sidecar-user/Dockerfile
* slow-sidecar/Dockerfile

**slow-sidecar** is a basic helloworld webserver in *V lang* (from another project [vhelloworld](https://github.com/zwindler/vhelloworld)) that's sleeps 5 seconds before serving on port 8081.

**sidecar-user** is a bash script that does a `curl` and `exit 1` if the `curl` call fails.

## Prerequisites

As said before, the feature is introduced in Kubernetes 1.28 as an alpha feature. If you use this version and want to test this, you have to specifically enable the feature flag.

As of Kubernetes 1.29, this feature graduated as beta and should be enabled by default on your cluster.

For more information see official documentation [kubernetes.io/docs/concepts/workloads/pods/sidecar-containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/).

## Without sidecar containers

First, deploy the CronJob without the feature on a cluster :

```bash
kubectl apply -f 1-cronjob-without-sidecar-container.yaml
```

It should fail because the "slow sidecar" container will not be ready when the "sidecar user" container tries to curl.

```bash
$ kubectl get pods
NAME                             READY   STATUS   RESTARTS   AGE
sidecar-cronjob-28689938-5n5x9   1/2     Error    0          9s

$ kubectl describe pods sidecar-cronjob-28689938-5n5x9
[...]
Containers:
  slow-sidecar:
[...]
    State:          Running
      Started:      Fri, 19 Jul 2024 15:38:03 +0200
    Ready:          True
[...]
  sidecar-user:
[...]
    State:          Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Fri, 19 Jul 2024 15:38:05 +0200
      Finished:     Fri, 19 Jul 2024 15:38:05 +0200
    Ready:          False
    Restart Count:  0
[...]
```

slow-sidecar is running just fine but our sidecar-user request failed because the sidecar was too slow to start.

Let's clean and try again

```bash
kubectl delete cronjob sidecar-cronjob 
```

Using init container isn't an option as well because the init container will never finish (it's not meant to) and the "sidecar user" container will wait forever it's turn. If you want to try, just convert slow-sidecar to an initContainer.

```diff
apiVersion: batch/v1
kind: CronJob
metadata:
  name: sidecar-cronjob
spec:
  schedule: "* * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: sidecar-user
            image: zwindler/sidecar-user
+         initContainers:
          - name: slow-sidecar
            image: zwindler/slow-sidecar
            ports:
            - containerPort: 8081
          restartPolicy: Never
```

And run it

```bash
$ kubectl apply -f 2-cronjob-with-init-container.yaml

$ kubectl get pods
NAME                             READY   STATUS     RESTARTS   AGE
sidecar-cronjob-28689955-lzbnf   0/1     Init:0/1   0          27s
#forever
```

## With sidecar containers

To avoid having this kind of race condition, let's update the manifest by converting the slow-sidecar to an initContainer BUT ALSO add a `restartPolicy: Always` in the manifest.

This "trick" is the way to tell Kubernetes to run this container as an initContainer but NOT wait until it finishes (it won't ever since it's a webserver listening on 8081 forever) to start the main app.

```diff
apiVersion: batch/v1
kind: CronJob
metadata:
  name: sidecar-cronjob
spec:
  schedule: "* * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: sidecar-user
            image: zwindler/sidecar-user
+         initContainers:
          - name: slow-sidecar
            image: zwindler/slow-sidecar
+           restartPolicy: Always
            ports:
            - containerPort: 8081
          restartPolicy: Never
```

**Note:** That's the official way to declare a sidecar container in Kubernetes. I haven't read (yet) the KEP so I can't tell why dev team didn't introduce a new `sidecarContainers` keyword in the Pod spec schema and reused the already existing `initContainers`.

```bash
$ kubectl apply -f 3-cronjob-with-sidecar-container.yaml
```

This time, the init container should launch and THEN only, the app:

```bash
$ kubectl get pods -w
NAME                             READY   STATUS    RESTARTS   AGE
sidecar-cronjob-28689958-zrmhh   0/2     Pending   0          0s
sidecar-cronjob-28689958-zrmhh   0/2     Pending   0          0s
sidecar-cronjob-28689958-zrmhh   0/2     Init:0/1   0          0s
sidecar-cronjob-28689958-zrmhh   1/2     PodInitializing   0          2s
sidecar-cronjob-28689958-zrmhh   1/2     Error             0          3s
```

In this particular example, we can see that it still fails...

## With sidecar containers AND startup probes

By default, the kubelet considers that the sidecar container is **up** as soon as the process in the container is running, and then begins to start the other initContainers in a standard way, and if there are none, start the main app container.

Sadly, in our case, the sidecar container is very slow (sleep 5), so the fact that the process is running is not an indication of the readiness of the sidecar...

We have to add a startupProbe so that Kubernetes knows WHEN to skip the init phase and start the main one.

> After a sidecar-style init container is running (the kubelet has set the started status for that init container to true), the kubelet then starts the next init container from the ordered .spec.initContainers list. That status either becomes true because there is a process running in the container and no startup probe defined, or as a result of its startupProbe succeeding.

```diff
apiVersion: batch/v1
kind: CronJob
metadata:
  name: sidecar-cronjob
spec:
  schedule: "* * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: sidecar-user
            image: zwindler/sidecar-user
          initContainers:
          - name: slow-sidecar
            image: zwindler/slow-sidecar
            restartPolicy: Always
            ports:
            - containerPort: 8081
+           startupProbe:
+             httpGet:
+               path: /
+               port: 8081
+             initialDelaySeconds: 5
+             periodSeconds: 1
+             failureThreshold: 5
          restartPolicy: Never
```

Let's try this one last time:

```bash
$ kubectl apply -f 4-cronjob-with-sidecar-container-and-startup-probe.yaml && kubectl get pods -w
cronjob.batch/sidecar-cronjob created
NAME                             READY   STATUS    RESTARTS   AGE
sidecar-cronjob-28689977-lt77c   0/2     Pending   0          0s
sidecar-cronjob-28689977-lt77c   0/2     Pending   0          0s
sidecar-cronjob-28689977-lt77c   0/2     Init:0/1   0          0s
sidecar-cronjob-28689977-lt77c   0/2     Init:0/1   0          1s
sidecar-cronjob-28689977-lt77c   0/2     PodInitializing   0          6s
sidecar-cronjob-28689977-lt77c   1/2     PodInitializing   0          6s
sidecar-cronjob-28689977-lt77c   1/2     Completed         0          7s
```

Hooray!

## If you don't have sidecarContainers enabled

Sadly this will require you to change your main app code or Docker image, but you can:

* add a retry policy in the sidecar-user app (this probably is a best practice though)
* add a script in the sidecar-user app that waits a bit (sleep) before trying to contact the sidecar

The first one is a best practice when dealing with microservices and you should consider it anyway.

The second one is a patch on a wooden leg. I strongly advise against it because startup speed can vary in the sidecar and adding too much delay in the app is bad as well when dealing with incidents and bugs (leading to other issues later).

## building the images

Just run `make docker-images`