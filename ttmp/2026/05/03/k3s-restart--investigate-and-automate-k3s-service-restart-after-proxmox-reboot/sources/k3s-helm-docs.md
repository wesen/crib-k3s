<article><div><p>Helm is the package management tool of choice for Kubernetes. Helm charts provide templating syntax for Kubernetes YAML manifest documents. With Helm, developers or cluster administrators can create configurable templates known as Charts, instead of just using static manifests. For more information about creating your own Chart catalog, check out the docs at <a href="https://helm.sh/docs/intro/quickstart/">https://helm.sh/docs/intro/quickstart/</a>.</p> <p>K3s does not require any special configuration to support Helm. Just be sure you have properly set the kubeconfig path as per the <a href="https://docs.k3s.io/cluster-access">cluster access</a> documentation.</p> <p>K3s includes a <a href="https://github.com/k3s-io/helm-controller/">Helm Controller</a> that manages installing, upgrading/reconfiguring, and uninstalling Helm charts using a HelmChart Custom Resource Definition (CRD). Paired with <a href="https://docs.k3s.io/installation/packaged-components">auto-deploying AddOn manifests</a>, installing a Helm chart on your cluster can be automated by creating a single file on disk.</p> <H2>Using the Helm Controller</H2> <p>The <a href="https://github.com/k3s-io/helm-controller#helm-controller">HelmChart Custom Resource</a> captures most of the options you would normally pass to the <code>helm</code> command-line tool.</p> <H3>HelmChart Field Definitions</H3>  <table><thead><tr><th>Field</th> <th>Default</th> <th>Description</th> <th>Helm Argument / Flag Equivalent</th></tr></thead> <tbody><tr><td>metadata.name</td> <td></td> <td>Helm Chart name</td> <td>NAME</td></tr> <tr><td>spec.chart</td> <td></td> <td>Helm Chart name in repository, or complete HTTPS URL to chart archive (.tgz)</td> <td>CHART</td></tr> <tr><td>spec.chartContent</td> <td></td> <td>Base64-encoded chart archive.tgz - overrides spec.chart</td> <td>CHART</td></tr> <tr><td>spec.targetNamespace</td> <td>default</td> <td>Helm Chart target namespace</td> <td><code>--namespace</code></td></tr> <tr><td>spec.createNamespace</td> <td>false</td> <td>Create target namespace if not present</td> <td><code>--create-namespace</code></td></tr> <tr><td>spec.version</td> <td></td> <td>Helm Chart version (when installing from repository)</td> <td><code>--version</code></td></tr> <tr><td>spec.repo</td> <td></td> <td>Helm Chart repository URL</td> <td><code>--repo</code></td></tr> <tr><td>spec.repoCA</td> <td></td> <td>Verify certificates of HTTPS-enabled servers using this CA bundle. Should be a string containing one or more PEM-encoded CA Certificates.</td><td><code>--ca-file</code></td></tr> <tr><td>spec.repoCAConfigMap</td> <td></td> <td>Reference to a ConfigMap containing CA Certificates to be be trusted by Helm. Can be used along with or instead of <code>repoCA</code></td> <td><code>--ca-file</code></td></tr> <tr><td>spec.plainHTTP</td> <td>false</td> <td>Use insecure HTTP connections for the chart download.</td><td><code>--plain-http</code></td></tr> <tr><td>spec.insecureSkipTLSVerify</td> <td>false</td> <td>Skip TLS certificate checks for the chart download.</td><td><code>--insecure-skip-tls-verify</code></td></tr> <tr><td>spec.helmVersion</td> <td>v3</td> <td>Helm version to use. Only <code>v3</code> is currently supported.</td><td></td></tr><tr><td>spec.bootstrap</td> <td>false</td> <td>Set to True if this chart is needed to bootstrap the cluster (Cloud Controller Manager, etc)</td> <td></td></tr> <tr><td>spec.jobImage</td> <td></td> <td>Specify the image to use when installing the helm chart. E.g. rancher/klipper-helm:v0.3.0.</td><td></td></tr><tr><td>spec.podSecurityContext</td> <td></td> <td>Custom <a href="https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#podsecuritycontext-v1-core"><code>v1.PodSecurityContext</code></a> for the Helm job pod</td> <td></td></tr> <tr><td>spec.securityContext</td> <td></td> <td>Custom <a href="https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#securitycontext-v1-core"><code>v1.SecurityContext</code></a> for the Helm job pod's containers</td> <td></td></tr> <tr><td>spec.backOffLimit</td> <td>1000</td> <td>Specify the number of retries before considering a job failed.</td><td></td></tr><tr><td>spec.timeout</td> <td>300s</td> <td>Timeout for Helm operations, as a <a href="https://pkg.go.dev/time#ParseDuration">duration string</a> (<code>300s</code>, <code>10m</code>, <code>1h</code>, etc)</td> <td><code>--timeout</code></td></tr> <tr><td>spec.failurePolicy</td> <td>reinstall</td> <td>Set to <code>abort</code> which case the Helm operation is aborted, pending manual intervention by the operator.</td><td></td></tr><tr><td>spec.authSecret</td> <td></td> <td>Reference to Secret of type <code>kubernetes.io/basic-auth</code> holding Basic auth credentials for the Chart repo.</td><td></td></tr><tr><td>spec.authPassCredentials</td> <td>false</td> <td>Pass Basic auth credentials to all domains.</td><td><code>--pass-credentials</code></td></tr> <tr><td>spec.dockerRegistrySecret</td> <td></td> <td>Reference to Secret of type <code>kubernetes.io/dockerconfigjson</code> holding Docker auth credentials for the OCI-based registry acting as the Chart repo.</td><td></td></tr><tr><td>spec.set</td> <td></td> <td>Override simple Chart values. These take precedence over options set via valuesContent.</td><td><code>--set</code> / <code>--set-string</code></td></tr> <tr><td>spec.valuesContent</td> <td></td> <td>Override complex Chart values via inline YAML content</td> <td><code>--values</code></td></tr> <tr><td>spec.valuesSecrets</td> <td></td> <td>Override complex Chart values via references to external Secrets</td> <td><code>--values</code></td></tr></tbody></table> <p>Content placed in <code>/var/lib/rancher/k3s/server/static/</code> can be accessed anonymously via the Kubernetes APIServer from within the cluster. This URL can be templated using the special variable <code>%{KUBERNETES_API}%</code> in the <code>spec.chart</code> field. For example, the packaged Traefik component loads its chart from <code>https://%{KUBERNETES_API}%/static/charts/traefik-VERSION.tgz</code>.</p> <p>Chart values are used in the following order, from least to greatest precedence:</p> <ol> <li>Chart default values</li> <li>HelmChart <code>spec.valuesContent</code></li> <li>HelmChart <code>spec.valuesSecrets</code> in listed order of secret name and keys</li> <li>HelmChartConfig <code>spec.valuesContent</code></li> <li>HelmChartConfig <code>spec.valuesSecrets</code> in listed order of secret name and keys</li> <li>HelmChart <code>spec.set</code></li> </ol> <p>Here's an example of how you might deploy Apache from the Bitnami chart repository, overriding some of the default chart values. Note that the HelmChart resource itself is in the <code>kube-system</code> namespace, but the chart's resources will be deployed to the <code>web</code> namespace, which is created in the same manifest. This can be useful if you want to keep your HelmChart resources separated from the resources they deploy.</p> <pre><code class="language-yaml" data-lang="yaml">apiVersion: v1
kind: Namespace
metadata:
  name: web
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: apache
  namespace: kube-system
spec:
  repo: https://charts.bitnami.com/bitnami
  chart: apache
  targetNamespace: web
  valuesContent: |-
    service:
      type: ClusterIP
    ingress:
      enabled: true
      hostname: www.example.com
    metrics:
      enabled: true</code></pre> <p>An example of deploying a helm chart from a private repo with authentication:</p> <pre><code class="language-yaml" data-lang="yaml">apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  namespace: kube-system
  name: example-app
spec:
  targetNamespace: example-namespace
  createNamespace: true
  version: v1.2.3
  chart: example-app
  repo: https://secure-repo.example.com
  authSecret:
    name: example-repo-auth
  repoCAConfigMap:
    name: example-repo-ca
  valuesContent: |-
    image:
      tag: v1.2.2
---
apiVersion: v1
kind: Secret
metadata:
  namespace: kube-system
  name: example-repo-auth
type: kubernetes.io/basic-auth
stringData:
  username: user
  password: pass
---
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: kube-system
  name: example-repo-ca
data:
  ca.crt: |-
    -----BEGIN CERTIFICATE-----
    &lt;YOUR CERTIFICATE&gt;
    -----END CERTIFICATE-----</code></pre> <H3>Chart Values from Secrets</H3> <p>Chart values can be read from externally-managed Secrets, instead of storing the values in the <code>spec.set</code> or <code>spec.valuesContent</code> fields. This should be done when passing confidential information such as credentials in to Charts that do not support referring to existing Secrets via the <code>existingSecret</code> pattern.</p> <p>As with other Secrets (<code>spec.authSecret</code> and <code>spec.dockerRegistrySecret</code>), Secrets referenced in <code>spec.valuesSecrets</code> must be in the same namespace as the HelmChart.</p> <p>Each listed <code>valuesSecrets</code> entry has the following fields:</p> <table><thead><tr><th>Field</th> <th>Description</th></tr></thead> <tbody><tr><td>name</td> <td>The name of the Secret. Required.</td></tr><tr><td>keys</td> <td>List of keys to read values from, values are used in the listed order. Required.</td></tr><tr><td>ignoreUpdates</td> <td>Mark this Secret as optional, and do not update the chart if the Secret changes. Optional, defaults to <code>false</code>.</td></tr></tbody></table> <ul> <li>If <code>ignoreUpdates</code> is set to <code>false</code> or unspecified, the Secret and all listed keys must exist. Any change to a referenced values Secret will cause the chart to be updated with new values.</li> <li>If <code>ignoreUpdates</code> is set to <code>true</code>, the Secret is used if it exists when the Chart is created, or updated due to any other change to related resources. Changes to the Secret will not cause the chart to be updated.</li> </ul> <p>An example of deploying a helm chart using an existing Secret with two keys:</p> <pre><code class="language-yaml" data-lang="yaml">apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  namespace: kube-system
  name: example-app
spec:
  targetNamespace: example-namespace
  createNamespace: true
  version: v1.2.3
  chart: example-app
  repo: https://repo.example.com
  valuesContent: |-
    image:
      tag: v1.2.2
  valuesSecrets:
    - name: example-app-custom-values
      ignoreUpdates: false
      keys:
        - someValues
        - moreValues
---
apiVersion: v1
kind: Secret
metadata:
  namespace: kube-system
  name: example-app-custom-values
stringData:
  moreValues: |-
    database:
      address: db.example.com
      username: user
      password: pass
  someValues: |-
    adminUser:
      create: true
      username: admin
      password: secret</code></pre> <H2>Customizing Packaged Components with HelmChartConfig</H2> <p>To allow overriding values for packaged components that are deployed as HelmCharts (such as Traefik), K3s supports customizing deployments via a HelmChartConfig resources. The HelmChartConfig resource must match the name and namespace of its corresponding HelmChart, and it supports providing additional <code>valuesContent</code>, which is passed to the <code>helm</code> command as an additional value file.</p> <H3>HelmChartConfig Field Definitions</H3> <table><thead><tr><th>Field</th> <th>Description</th></tr></thead> <tbody><tr><td>metadata.name</td> <td>Helm Chart name - must match the HelmChart resource name.</td></tr><tr><td>spec.valuesContent</td> <td>Override complex default Chart values via YAML file content.</td></tr><tr><td>spec.valuesSecrets</td> <td>Override complect default Chart values via external Secrets.</td></tr><tr><td>spec.failurePolicy</td> <td>Set to <code>abort</code> which case the Helm operation is aborted, pending manual intervention by the operator.</td></tr></tbody></table>  <p>For example, to customize the packaged Traefik ingress configuration, you can create a file named <code>/var/lib/rancher/k3s/server/manifests/traefik-config.yaml</code> and populate it with the following content:</p> <pre><code class="language-yaml" data-lang="yaml">apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    image:
      repository: docker.io/library/traefik
      tag: 3.3.5
    ports:
      web:
        forwardedHeaders:
          trustedIPs:
            - 10.0.0.0/8</code></pre></div></article>