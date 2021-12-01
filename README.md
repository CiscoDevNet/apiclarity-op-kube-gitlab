# OnPrem K3s Build of Gitlab and Gitlab CICD

This repo is meant to be a guide to build up a k3s kube cluster, gitlab, and APIClarity demo from scratch.

## PreReqs
* On Dev machine: kubectl, helm and istioctl
* general understanding of using kubernetes and kube config files
* Need 3 fresh Ubuntu VMs.
* Access to DNS and domain settings for your environment.

> Note: How you do this is up to you. But I am using multipass to do this. I have found that you will need 3 VMs with at least 20GB of RAM for spinning up Gitlab using 18GB of RAM per node at least at first.

## K3s setup - perfect for a small dev cluster for this purpose

### Primary Ubuntu Node - install command

```
curl -sfL https://get.k3s.io |INSTALL_K3S_VERSION="v1.19.15+k3s1" INSTALL_K3S_EXEC="--no-deploy traefik --disable servicelb" sh -
```

Copy the kube config file and IP address of host machine to use on your host machine replace the URL on for the server on line 5 with the ip address you might also want to replace the places where default is used reference the example_k3s_start_config file in this folder

`ip addr show` 

Find your external facing interface and ip associated

```
sudo cat /etc/rancher/k3s/k3s.yaml
```

* copy that information to a file on your dev computer and use with kubectl

### Setup secondary Nodes

* FROM YOUR PRIMARY UBUNTU NODE Get your node token

```
sudo cat /var/lib/rancher/k3s/server/node-token
```

* Next SSH / Console into your Secondary Nodes and use the node-token from the primary node with the below command in the CLI

```
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.19.15+k3s1" K3S_URL=https://<PRIMARY_NODE_IP:6443 K3S_TOKEN=<node-token> sh -
```

* Log into your other Ubuntu node and repeat the above steps for the secondary nodes.

Once this is done and if you have added the k3s config to your kubectl on your dev machine you should no longer need to SSH/console into your Ubuntu VMs/Nodes



## Metallb Install

kubectl create ns metallb-system

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/main/manifests/metallb.yaml

* Change the below referenced file, on line 12 to match an IP scheme of your choosing before applying the below command

```
kubectl apply -f metallb_install/metallb-init-config.yaml
```


## Install your own ingress

> We will change some settings on gitlab helm chart later to correct it from trying to use its own ingress implementation.

```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.0.0/deploy/static/provider/cloud/deploy.yaml
```


## Cert Manager Install

kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.5.3/cert-manager.yaml


## GitLab install 

* ONLY USE IF ON LOCAL NETWORK: Use self-signed certs if only a local network

```
kubectl apply -f gitlab_install/gitlab-cert-cluster-issuer.yaml
```

* IF ON A PUBLICLY ACCESSIBLE k3s cluster, use the following

```
kubectl apply -f gitlab_install/gitlab-cert-cluster-letsencrypt.yaml
```

* Now for the actual Gitlab install, use the following commands

```
helm repo add gitlab https://charts.gitlab.io/
helm repo update
```

* On the below command you will need to change a few parts of the command.
* Change `--set global.hosts.domain=gl.example.com` to a subdomain that works for your setup and DNS entries.
* Change `--set gitlab-runner.runners.extra_hosts="gitlab.gl.example.com:0.0.0.0"` the hosts domain and IP address to match your gitlab domain and the IP address of your ingress from your nginx ingress setup.
> Note: you can get your ingress IP address by finding it using `kubectl get svc --all-namspaces`
* Lastly change IP address to match your ingress for `--set global.hosts.externalIP=0.0.0.0`

* Utilize your updated command values that should similar to below.

```
helm install gitlab gitlab/gitlab --timeout 600s --set gitlab-runner.runners.privileged=true  --set gitlab-runner.runners.extra_hosts="gitlab.gl.example.com:0.0.0.0" --set gitlab-runner.certsSecretName=tls-secret-gl-gitlab --set global.hosts.domain=gl.example.com --set global.hosts.externalIP=0.0.0.0 --set certmanager.install=false --set global.ingress.configureCertmanager=false --set nginx-ingress.enabled=false --set global.kas.enabled=true
```


* Change gitlab-ingress.yaml file to reflect the domain names  you are able to use through external cluster DNS. Specifically change any host entries on that file on lines 10, 23, 37, 46, 59, 68, ,81, 94.

* Once you have made the changes to the gitlab-ingress.yaml file, utlize the below commands.

```
kubectl delete -f gitlab_install/gitlab-ingress.yaml

kubectl apply -f gitlab_install/gitlab-ingress.yaml
```

> wait for everything to be available, use below command to monitor

```
kubectl get deploy -w
```

* get your root password using the below command

```
kubectl get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}' | base64 --decode ; echo
```

* login in with username: root and the password from the command below using the domain name you setup for gitlab. example: https://gitlab.gl.example.com


### USE IF ON LOCAL NETWORK: Patch DNS entries

* Update the file on lines 47, 103, 105, 110 to reflect the correct domain and IP addrss of your nginx ingress.

* Once you have updated the file use the following command. 

```
kubectl apply -f gitlab_install/gitlab-runner-deploy-local-no-dns-patch.yaml
```

### How to add an existing Kube cluster to Gitlab
* On your gitlab site go to the admin clusters section. example, https://gitlab.gl.example.com/admin/clusters

* Click the Connect Existing Cluster Tab
* Give your cluster a name
* Update the API URL for the cluster - per gitlabs docs...
> API URL (required) - It’s the URL that GitLab uses to access the Kubernetes API. Kubernetes exposes several APIs, we want the “base” URL that is common to all of them. For example, https://kubernetes.example.com rather than https://kubernetes.example.com/api/v1
* get the API URL by using the following command with kubectl

```
kubectl cluster-info | grep -E 'Kubernetes master|Kubernetes control plane' | awk '/http/ {print $NF}'
```

* Next use `kubectl get secret` and find find a secret with a name similar to default-token-xxxxx and replace <secret name> with that secret name `kubectl get secret <secret name> -o jsonpath="{['data']['ca\.crt']}" | base64 --decode`
* You command should look similar to below 

```
kubectl get secret default-token-pqw4w -o jsonpath="{['data']['ca\.crt']}" | base64 --decode
```

* For the CA cert issue the following command and enter the resulting output in the correct field

```
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep gitlab | awk '{print $1}')
```

* Next add a service  account and cluster role binding with the following command.

```
kubectl apply -f gitlab_install/gitlab-admin-service-account.yaml
```

* Then adding a Gitlab Runner User Account Token

```
kubectl apply -f gitlab_install/gitlab-service-account.yaml
```

* Get the token using the following command

```
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep gitlab | awk '{print $1}')
```

* Update the token field with output from the previous command.

> Note if you have problems with your runner working with those settings, you can grant permissive mode using the following command

```
kubectl create clusterrolebinding permissive-binding \
  --clusterrole=cluster-admin \
  --user=admin \
  --user=kubelet \
  --group=system:serviceaccounts
```

## Fire Up the CICD with our sample App /API Clarity and Istio.

First we need to clone the sample app repo from Github to our Gitlab repo.

* Login to Gitlab with your user creds
* Click the New Project button
* Click Import project
* Click the repo by URL button
* Copy the URL, https://github.com/CiscoDevNet/microservices-demo, to the “Git repository URL” field
* Rename the project and slug and change the visibility level as desired for your preferences. For the purposes of this app I will not change any of that information.
* Click Create Project

Once that is done we are going to make a small change to the README.md file in Gitlab to kick off the install.

* Navigate to the README.md file and click edit, modify the following URL to your correct domain and then navigate there... example: https://gitlab.gl.example.com/root/microservices-demo/-/edit/master/README.md

* Add a line with some text at the bottom of the edit section and then click "Commit changes".
* Navigate to the pipeline for your new deployment example: https://gitlab.example.com/root/microservices-demo/-/pipelines
* Click Either here it says Pending or Running and then click where it says deploy.

You should see the out put where it is deploying.

> What is Happening??? - The Gitlab runner is checking if Istio is installed, if it is not, it will install it. It then adds the namespaces for sock-shop and APIClarity, labels the sock-shop namespace for istio, deploys sock-shop, deploys APIClarity and then updates the sock-shop deployment to funnel HTTP requests to APIClarity.

> After the first deployment, everytime the code is updated it will redeploy the app with the latest updates and update APIClarity accordingly and as needed.

## Now lets Use APIClarity and the sample app generate some traffic and view the APIClarity results.

* Using an IP address tied to a Kubernetes node go to http://<kube-node-ip>:30001 and click around / navigate around the site to generate some traffic.
* Next issue the following command

```
kubectl port-forward -n apiclarity svc/apiclarity 9999:8080
```
* Then in your browser visit http://localhost:9999 or http://127.0.0.1:9999 to check out APIClarity



If you want to do a fresh install of of APIClarity, the demo microservice, and istio use the following bash file using the following commands.

```
chmod +x uninstall_istio_apiclarity_sockshop.sh

./uninstall_istio_apiclarity_sockshop.sh
```
