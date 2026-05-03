<div class="github post">
			<div class="post-content">
				<div class="markdown-body NewMarkdownViewer-module__safe-html-box__ZT1eD">
<p dir="auto"><strong>Environmental Info:</strong><br>
K3s Version:</p>

<div class="snippet-clipboard-content notranslate position-relative overflow-auto" data-snippet-clipboard-copy-content="root@<hidden>:/home/devuser# k3s -v
k3s version v1.25.4+k3s1 (0dc63334)
go version go1.19.3"><pre class="notranslate"><code class="notranslate">root@&lt;hidden&gt;:/home/devuser# k3s -v
k3s version v1.25.4+k3s1 (0dc63334)
go version go1.19.3
</code></pre></div>
<p dir="auto">Node(s) CPU architecture, OS, and Version:</p>

<p dir="auto">AWS EC2 instance:</p>
<div class="snippet-clipboard-content notranslate position-relative overflow-auto" data-snippet-clipboard-copy-content="root@<hidden>:/home/<hidden># cat /etc/lsb-release
DISTRIB_ID=Ubuntu
DISTRIB_RELEASE=20.04
DISTRIB_CODENAME=focal
DISTRIB_DESCRIPTION=&quot;Ubuntu 20.04.6 LTS&quot;
root@<hidden>:/home/<hidden>#
root@<hidden>:/home/<hidden># uname -a
Linux <hidden> 5.11.0-1016-aws #17~20.04.1-Ubuntu SMP Thu Aug 12 05:39:36 UTC 2021 x86_64 x86_64 x86_64 GNU/Linux
root@<hidden>:/home/<hidden># cat /proc/cpuinfo | grep 'vendor' | uniq
vendor_id	: AuthenticAMD
root@<hidden>:/home/<hidden># cat /proc/cpuinfo | grep 'model name' | uniq
model name	: AMD EPYC 7R32
root@<hidden>:/home/<hidden># cat /proc/cpuinfo | grep processor | wc -l
32"><pre class="notranslate"><code class="notranslate">root@&lt;hidden&gt;:/home/&lt;hidden&gt;# cat /etc/lsb-release
DISTRIB_ID=Ubuntu
DISTRIB_RELEASE=20.04
DISTRIB_CODENAME=focal
DISTRIB_DESCRIPTION="Ubuntu 20.04.6 LTS"
root@&lt;hidden&gt;:/home/&lt;hidden&gt;#
root@&lt;hidden&gt;:/home/&lt;hidden&gt;# uname -a
Linux &lt;hidden&gt; 5.11.0-1016-aws #17~20.04.1-Ubuntu SMP Thu Aug 12 05:39:36 UTC 2021 x86_64 x86_64 x86_64 GNU/Linux
root@&lt;hidden&gt;:/home/&lt;hidden&gt;# cat /proc/cpuinfo | grep 'vendor' | uniq
vendor_id	: AuthenticAMD
root@&lt;hidden&gt;:/home/&lt;hidden&gt;# cat /proc/cpuinfo | grep 'model name' | uniq
model name	: AMD EPYC 7R32
root@&lt;hidden&gt;:/home/&lt;hidden&gt;# cat /proc/cpuinfo | grep processor | wc -l
32
</code></pre></div>
<p dir="auto">Cluster Configuration: 1 server only</p>

<p dir="auto"><strong>Describe the bug:</strong></p>

<p dir="auto">cloud-controller-manager exited due to <code class="notranslate">Apr 20 13:02:35 &lt;hidden&gt; k3s[84782]: time="2023-04-20T13:02:35+02:00" level=error msg="cloud-controller-manager exited: unable to load configmap based request-header-client-ca-file: configmaps \"extension-apiserver-authentication\" is forbidden: User \"k3s-cloud-controller-manager\" cannot get resource \"configmaps\" in API group \"\" in the namespace \"kube-system\""</code>, the role was created at <code class="notranslate">"2023-04-20T13:02:30Z"</code> and the role binding was created at <code class="notranslate">"2023-04-20T13:02:36Z"</code>. It means that at the moment when cloud-controller-manager tries to get config map, it has not permissions due to lack of role binding. And it causes that taint <code class="notranslate">node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule</code> remains on the node and pods stay in <code class="notranslate">pending</code> state.</p>
<p dir="auto">Restarting the k3s service resolves the issue, cloud-controller is restarted and the role binding already exists, that is probably why it is working after k3s restart, but it is not how it should work.</p>
<p dir="auto"><strong>Steps To Reproduce:</strong></p>

<ul dir="auto">
<li>Installed K3s:</li>
</ul>
<div class="snippet-clipboard-content notranslate position-relative overflow-auto" data-snippet-clipboard-copy-content="INSTALL_K3S_VERSION=v1.25.4+k3s1 INSTALL_K3S_EXEC=&quot;--disable traefik --service-node-port-range 30000-30050
--kube-apiserver-arg=enable-admission-plugins=NodeRestriction,ServiceAccount --kube-apiserver-arg=request-timeout=5m0s
--kube-apiserver-arg=audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log
--kube-apiserver-arg=tls-cipher-suites=TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
--kube-apiserver-arg=audit-log-maxbackup=10 --kube-controller-manager-arg=terminated-pod-gc-threshold=1000
--kube-controller-manager-arg=leader-elect-lease-duration=30s --kube-controller-manager-arg=leader-elect-renew-deadline=20s
--kube-controller-manager-arg=bind-address=127.0.0.1 --kube-scheduler-arg=bind-address=127.0.0.1
--kubelet-arg=streaming-connection-idle-timeout=5m --kubelet-arg=rotate-server-certificates=true
--kubelet-arg=eviction-hard=imagefs.available<20Gi,memory.available<100Mi,nodefs.available<20Gi,nodefs.inodesFree<5%
--kubelet-arg=eviction-minimum-reclaim=imagefs.available=1Gi,nodefs.available=1Gi&quot; ./k3s_installer.sh"><pre class="notranslate"><code class="notranslate">INSTALL_K3S_VERSION=v1.25.4+k3s1 INSTALL_K3S_EXEC="--disable traefik --service-node-port-range 30000-30050
--kube-apiserver-arg=enable-admission-plugins=NodeRestriction,ServiceAccount --kube-apiserver-arg=request-timeout=5m0s
--kube-apiserver-arg=audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log
--kube-apiserver-arg=tls-cipher-suites=TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
--kube-apiserver-arg=audit-log-maxbackup=10 --kube-controller-manager-arg=terminated-pod-gc-threshold=1000
--kube-controller-manager-arg=leader-elect-lease-duration=30s --kube-controller-manager-arg=leader-elect-renew-deadline=20s
--kube-controller-manager-arg=bind-address=127.0.0.1 --kube-scheduler-arg=bind-address=127.0.0.1
--kubelet-arg=streaming-connection-idle-timeout=5m --kubelet-arg=rotate-server-certificates=true
--kubelet-arg=eviction-hard=imagefs.available&lt;20Gi,memory.available&lt;100Mi,nodefs.available&lt;20Gi,nodefs.inodesFree&lt;5%
--kubelet-arg=eviction-minimum-reclaim=imagefs.available=1Gi,nodefs.available=1Gi" ./k3s_installer.sh
</code></pre></div>
<p dir="auto">I do not have steps to reproduce, as it occurs periodically.</p>
<p dir="auto"><strong>Expected behavior:</strong></p>

<p dir="auto">cloud-controller-manager running properly, maybe it should ensure that role and role binding are created before trying to get the configmap.</p>
<p dir="auto"><strong>Actual behavior:</strong></p>

<p dir="auto">cloud-controller-manager exited, it was not able to get the required config map due to lack of permissions.</p>
<p dir="auto"><strong>Additional context / logs:</strong></p>

<p dir="auto">role details:</p>
<div class="snippet-clipboard-content notranslate position-relative overflow-auto" data-snippet-clipboard-copy-content="root@<hidden>:~# kubectl get role -n kube-system extension-apiserver-authentication-reader -o yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: &quot;true&quot;
  creationTimestamp: &quot;2023-04-20T13:02:30Z&quot;
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: extension-apiserver-authentication-reader
  namespace: kube-system
  resourceVersion: &quot;176&quot;
  uid: bd705934-437e-45e4-9233-b6982d11d1d0
rules:
- apiGroups:
  - &quot;&quot;
  resourceNames:
  - extension-apiserver-authentication
  resources:
  - configmaps
  verbs:
  - get
  - list
  - watch"><pre class="notranslate"><code class="notranslate">root@&lt;hidden&gt;:~# kubectl get role -n kube-system extension-apiserver-authentication-reader -o yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  creationTimestamp: "2023-04-20T13:02:30Z"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: extension-apiserver-authentication-reader
  namespace: kube-system
  resourceVersion: "176"
  uid: bd705934-437e-45e4-9233-b6982d11d1d0
rules:
- apiGroups:
  - ""
  resourceNames:
  - extension-apiserver-authentication
  resources:
  - configmaps
  verbs:
  - get
  - list
  - watch
</code></pre></div>
<p dir="auto">role binding details:</p>
<div class="snippet-clipboard-content notranslate position-relative overflow-auto" data-snippet-clipboard-copy-content="root@<hidden>:~# kubectl -n kube-system get rolebinding -o yaml k3s-cloud-controller-manager-authentication-reader
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  annotations:
    objectset.rio.cattle.io/applied: <hidden>
    objectset.rio.cattle.io/id: &quot;&quot;
    objectset.rio.cattle.io/owner-gvk: k3s.cattle.io/v1, Kind=Addon
    objectset.rio.cattle.io/owner-name: ccm
    objectset.rio.cattle.io/owner-namespace: kube-system
  creationTimestamp: &quot;2023-04-20T13:02:36Z&quot;
  labels:
    objectset.rio.cattle.io/hash: 5089468545c5482413c7f05e837e9b88f02ad052
  name: k3s-cloud-controller-manager-authentication-reader
  namespace: kube-system
  resourceVersion: &quot;247&quot;
  uid: b8168fc0-0d35-461a-b5a4-8d41a7215c4d
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: extension-apiserver-authentication-reader
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: k3s-cloud-controller-manager
  namespace: kube-system"><pre class="notranslate"><code class="notranslate">root@&lt;hidden&gt;:~# kubectl -n kube-system get rolebinding -o yaml k3s-cloud-controller-manager-authentication-reader
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  annotations:
    objectset.rio.cattle.io/applied: &lt;hidden&gt;
    objectset.rio.cattle.io/id: ""
    objectset.rio.cattle.io/owner-gvk: k3s.cattle.io/v1, Kind=Addon
    objectset.rio.cattle.io/owner-name: ccm
    objectset.rio.cattle.io/owner-namespace: kube-system
  creationTimestamp: "2023-04-20T13:02:36Z"
  labels:
    objectset.rio.cattle.io/hash: 5089468545c5482413c7f05e837e9b88f02ad052
  name: k3s-cloud-controller-manager-authentication-reader
  namespace: kube-system
  resourceVersion: "247"
  uid: b8168fc0-0d35-461a-b5a4-8d41a7215c4d
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: extension-apiserver-authentication-reader
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: k3s-cloud-controller-manager
  namespace: kube-system
</code></pre></div>
<p dir="auto">journalctl logs related to cloud controller:</p>
<div class="snippet-clipboard-content notranslate position-relative overflow-auto" data-snippet-clipboard-copy-content="root@<hidden>:~# journalctl -u k3s.service | grep cloud-controller
Apr 20 13:02:25 <hidden>k3s[84782]: time=&quot;2023-04-20T13:02:25+02:00&quot; level=info msg=&quot;certificate CN=k3s-cloud-controller-manager signed by CN=k3s-client-ca@1681995745: notBefore=2023-04-20 13:02:25 +0000 UTC notAfter=2024-04-19 13:02:25 +0000 UTC&quot;
Apr 20 13:02:25 <hidden> k3s[84782]: time=&quot;2023-04-20T13:02:25+02:00&quot; level=info msg=&quot;Running cloud-controller-manager --allocate-node-cidrs=true --authentication-kubeconfig=/var/lib/rancher/k3s/server/cred/cloud-controller.kubeconfig --authorization-kubeconfig=/var/lib/rancher/k3s/server/cred/cloud-controller.kubeconfig --bind-address=127.0.0.1 --cloud-config=/var/lib/rancher/k3s/server/etc/cloud-config.yaml --cloud-provider=k3s --cluster-cidr=10.42.0.0/16 --configure-cloud-routes=false --controllers=*,-route --kubeconfig=/var/lib/rancher/k3s/server/cred/cloud-controller.kubeconfig --leader-elect=false --leader-elect-resource-name=k3s-cloud-controller-manager --node-status-update-frequency=1m0s --profiling=false&quot;
Apr 20 13:02:31 <hidden> k3s[84782]: time=&quot;2023-04-20T13:02:31+02:00&quot; level=info msg=&quot;Waiting for cloud-controller-manager privileges to become available&quot;
Apr 20 13:02:35 <hidden> k3s[84782]: unable to load configmap based request-header-client-ca-file: configmaps &quot;extension-apiserver-authentication&quot; is forbidden: User &quot;k3s-cloud-controller-manager&quot; cannot get resource &quot;configmaps&quot; in API group &quot;&quot; in the namespace &quot;kube-system&quot;
Apr 20 13:02:35 <hidden> k3s[84782]: Error: unable to load configmap based request-header-client-ca-file: configmaps &quot;extension-apiserver-authentication&quot; is forbidden: User &quot;k3s-cloud-controller-manager&quot; cannot get resource &quot;configmaps&quot; in API group &quot;&quot; in the namespace &quot;kube-system&quot;
Apr 20 13:02:35 <hidden> k3s[84782]:   cloud-controller-manager [flags]
Apr 20 13:02:35 <hidden> k3s[84782]:       --leader-elect-resource-name string        The name of resource object that is used for locking during leader election. (default &quot;cloud-controller-manager&quot;)
Apr 20 13:02:35 <hidden> k3s[84782]:   -h, --help                             help for cloud-controller-manager
Apr 20 13:02:35 <hidden> k3s[84782]: time=&quot;2023-04-20T13:02:35+02:00&quot; level=error msg=&quot;cloud-controller-manager exited: unable to load configmap based request-header-client-ca-file: configmaps \&quot;extension-apiserver-authentication\&quot; is forbidden: User \&quot;k3s-cloud-controller-manager\&quot; cannot get resource \&quot;configmaps\&quot; in API group \&quot;\&quot; in the namespace \&quot;kube-system\&quot;&quot;
Apr 20 13:02:36 <hidden> k3s[84782]: time=&quot;2023-04-20T13:02:36+02:00&quot; level=info msg=&quot;Slow SQL (started: 2023-04-20 13:02:33.991100151 +000 CEST m=+15.104670164) (total time: 2.104021479s): INSERT INTO kine(name, created, deleted, create_revision, prev_revision, lease, value, old_value) values(?, ?, ?, ?, ?, ?, ?, ?) : [[/registry/clusterrolebindings/k3s-cloud-controller-manager-auth-delegator 1 0 0 0 0 [<hidden>]
Apr 20 13:02:36 <hidden> k3s[84782]: I0420 13:02:36.095642   84782 trace.go:205] Trace[1885216390]: &quot;Create etcd3&quot; audit-id:239071e7-361e-4035-83d9-c50e59baa653,key:/clusterrolebindings/k3s-cloud-controller-manager-auth-delegator,type:*rbac.ClusterRoleBinding (20-Apr-2023 13:02:33.990) (total time: 2105ms):"><pre class="notranslate"><code class="notranslate">root@&lt;hidden&gt;:~# journalctl -u k3s.service | grep cloud-controller
Apr 20 13:02:25 &lt;hidden&gt;k3s[84782]: time="2023-04-20T13:02:25+02:00" level=info msg="certificate CN=k3s-cloud-controller-manager signed by CN=k3s-client-ca@1681995745: notBefore=2023-04-20 13:02:25 +0000 UTC notAfter=2024-04-19 13:02:25 +0000 UTC"
Apr 20 13:02:25 &lt;hidden&gt; k3s[84782]: time="2023-04-20T13:02:25+02:00" level=info msg="Running cloud-controller-manager --allocate-node-cidrs=true --authentication-kubeconfig=/var/lib/rancher/k3s/server/cred/cloud-controller.kubeconfig --authorization-kubeconfig=/var/lib/rancher/k3s/server/cred/cloud-controller.kubeconfig --bind-address=127.0.0.1 --cloud-config=/var/lib/rancher/k3s/server/etc/cloud-config.yaml --cloud-provider=k3s --cluster-cidr=10.42.0.0/16 --configure-cloud-routes=false --controllers=*,-route --kubeconfig=/var/lib/rancher/k3s/server/cred/cloud-controller.kubeconfig --leader-elect=false --leader-elect-resource-name=k3s-cloud-controller-manager --node-status-update-frequency=1m0s --profiling=false"
Apr 20 13:02:31 &lt;hidden&gt; k3s[84782]: time="2023-04-20T13:02:31+02:00" level=info msg="Waiting for cloud-controller-manager privileges to become available"
Apr 20 13:02:35 &lt;hidden&gt; k3s[84782]: unable to load configmap based request-header-client-ca-file: configmaps "extension-apiserver-authentication" is forbidden: User "k3s-cloud-controller-manager" cannot get resource "configmaps" in API group "" in the namespace "kube-system"
Apr 20 13:02:35 &lt;hidden&gt; k3s[84782]: Error: unable to load configmap based request-header-client-ca-file: configmaps "extension-apiserver-authentication" is forbidden: User "k3s-cloud-controller-manager" cannot get resource "configmaps" in API group "" in the namespace "kube-system"
Apr 20 13:02:35 &lt;hidden&gt; k3s[84782]:   cloud-controller-manager [flags]
Apr 20 13:02:35 &lt;hidden&gt; k3s[84782]:       --leader-elect-resource-name string        The name of resource object that is used for locking during leader election. (default "cloud-controller-manager")
Apr 20 13:02:35 &lt;hidden&gt; k3s[84782]:   -h, --help                             help for cloud-controller-manager
Apr 20 13:02:35 &lt;hidden&gt; k3s[84782]: time="2023-04-20T13:02:35+02:00" level=error msg="cloud-controller-manager exited: unable to load configmap based request-header-client-ca-file: configmaps \"extension-apiserver-authentication\" is forbidden: User \"k3s-cloud-controller-manager\" cannot get resource \"configmaps\" in API group \"\" in the namespace \"kube-system\""
Apr 20 13:02:36 &lt;hidden&gt; k3s[84782]: time="2023-04-20T13:02:36+02:00" level=info msg="Slow SQL (started: 2023-04-20 13:02:33.991100151 +000 CEST m=+15.104670164) (total time: 2.104021479s): INSERT INTO kine(name, created, deleted, create_revision, prev_revision, lease, value, old_value) values(?, ?, ?, ?, ?, ?, ?, ?) : [[/registry/clusterrolebindings/k3s-cloud-controller-manager-auth-delegator 1 0 0 0 0 [&lt;hidden&gt;]
Apr 20 13:02:36 &lt;hidden&gt; k3s[84782]: I0420 13:02:36.095642   84782 trace.go:205] Trace[1885216390]: "Create etcd3" audit-id:239071e7-361e-4035-83d9-c50e59baa653,key:/clusterrolebindings/k3s-cloud-controller-manager-auth-delegator,type:*rbac.ClusterRoleBinding (20-Apr-2023 13:02:33.990) (total time: 2105ms):
</code></pre></div></div>
			</div>
		</div>