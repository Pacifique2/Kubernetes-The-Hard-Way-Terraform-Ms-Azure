resource "tls_private_key" "devo_kube_ca" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "tls_self_signed_cert" "devo_kube_ca" {
  key_algorithm   = "${tls_private_key.devo_kube_ca.algorithm}"
  private_key_pem = "${tls_private_key.devo_kube_ca.private_key_pem}"

  subject {
    common_name         = "Kubernetes"
    organization        = "Kube-devoteam"
    country             = "FR"
    locality            = "Hauts-de-Seine"
    organizational_unit = "CA"
    province            = "Paris"
  }

  is_ca_certificate     = true
  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "cert_signing",
    "client_auth",
    "server_auth"
  ]
}

resource "local_file" "devo_kube_ca_key" {
  content  = "${tls_private_key.devo_kube_ca.private_key_pem}"
  filename = "./tls-certs/client-server/ca-key.pem"
}

resource "local_file" "devo_kube_ca_crt" {
  content  = "${tls_self_signed_cert.devo_kube_ca.cert_pem}"
  filename = "./tls-certs/client-server/ca.pem"
}

resource "null_resource" "devo_ca_certs" {
  count = "${var.nodes_count}"
  #"${length(var.node_dns_names)}"
  
  connection {
    type         = "ssh"
    host = "${element(var.node_dns_names,count.index)}"
    user         = "${var.api_server_username}"
    password     = "${var.api_server_password}"
    private_key  = "${file("~/.ssh/kube-devolab_id_rsa")}"
    timeout      =  "1m"
    agent        = true
  }

  provisioner "file" {
    source      = "./tls-certs/client-server/ca.pem"
    destination = "~/ca.pem"
  }
#####################i#############################################################################################################
  provisioner "file" {
    source      = "./tls-certs/client-server/ca-key.pem"
    destination = "~/ca-key.pem"
  }
} 

######################################################################################################################################
# Admin  users certificate and private key 

######################################################################################################################################
resource "tls_private_key" "devo_kube_admin" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "tls_cert_request" "devo_kube_admin" {
  key_algorithm   = "${tls_private_key.devo_kube_admin.algorithm}"
  private_key_pem = "${tls_private_key.devo_kube_admin.private_key_pem}"

  subject {
    common_name         = "admin"
    organization        = "Kube-devoteam"
    country             = "FR"
    locality            = "Hauts-de-Seine"
    organizational_unit = "Kubernetes The Hard Way"
    province            = "Paris"
  }
}

resource "tls_locally_signed_cert" "devo_kube_admin" {
  cert_request_pem   = "${tls_cert_request.devo_kube_admin.cert_request_pem}"
  ca_key_algorithm   = "${tls_private_key.devo_kube_ca.algorithm}"
  ca_private_key_pem = "${tls_private_key.devo_kube_ca.private_key_pem}"
  ca_cert_pem        = "${tls_self_signed_cert.devo_kube_ca.cert_pem}"

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "cert_signing",
    "client_auth",
    "server_auth",
  ]
}

resource "local_file" "kube_admin_key" {
  content  = "${tls_private_key.devo_kube_admin.private_key_pem}"
  filename = "./tls-certs/client-server/admin-key.pem"
}

resource "local_file" "kube_admin_crt" {
  content  = "${tls_locally_signed_cert.devo_kube_admin.cert_pem}"
  filename = "./tls-certs/client-server/admin.pem"
}


####################################################################################
# Kubelet client certificates for each worker node
####################################################################################

resource "tls_private_key" "kubelet_worker_prkey" {
  count = "${length(var.kube_worker_node_names)}"

  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "tls_cert_request" "kubelet_worker_csr" {
  key_algorithm   = "${tls_private_key.kubelet_worker_prkey.*.algorithm[count.index]}"
  private_key_pem = "${tls_private_key.kubelet_worker_prkey.*.private_key_pem[count.index]}"

  count = "${length(var.kube_worker_node_names)}"

  lifecycle {
    ignore_changes = ["id"]
  }

  ip_addresses = ["${element(var.worker_node_ips, count.index)}"]

  subject {
    common_name         = "system:node:${element(var.kube_worker_node_names, count.index)}"
    organization        = "system:nodes"
    country             = "FR"
    locality            = "Hauts-de-Seine"
    organizational_unit = "Kubernetes The Hard Way"
    province            = "Paris"
  }
}

resource "tls_locally_signed_cert" "kubelet_worker_ca" {
  count = "${length(var.kube_worker_node_names)}"

  cert_request_pem   = "${tls_cert_request.kubelet_worker_csr.*.cert_request_pem[count.index]}"
  ca_key_algorithm   = "${tls_private_key.devo_kube_ca.algorithm}"
  ca_private_key_pem = "${tls_private_key.devo_kube_ca.private_key_pem}"
  ca_cert_pem        = "${tls_self_signed_cert.devo_kube_ca.cert_pem}"

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "cert_signing",
    "client_auth",
    "server_auth",
  ]
}

resource "local_file" "kubelet_worker_key" {
  count = "${length(var.kube_worker_node_names)}"

  content  = "${tls_private_key.kubelet_worker_prkey.*.private_key_pem[count.index]}"
  filename = "./tls-certs/kubelet/${element(var.kube_worker_node_names, count.index)}-key.pem"
}

resource "local_file" "kubelet_crt" {
  count = "${length(var.kube_worker_node_names)}"

  content  = "${tls_locally_signed_cert.kubelet_worker_ca.*.cert_pem[count.index]}"
  filename = "./tls-certs/kubelet/${element(var.kube_worker_node_names, count.index)}.pem"
}

resource "null_resource" "kubelet_certs" {
  count = "${length(var.kube_worker_node_names)}"

  depends_on = ["local_file.kubelet_crt"]
  depends_on = ["local_file.kubelet_worker_key"]
  
  connection {
    type         = "ssh"
    host = "${element(var.worker_nodes_dns_names,count.index)}"
    user         = "${var.worker_username}"
    password     = "${var.worker_password}"
    private_key  = "${file("~/.ssh/kube-devolab_id_rsa")}"
    timeout      =  "1m"
    agent        = true
  }

  provisioner "file" {
    source      = "./tls-certs/kubelet/${element(var.kube_worker_node_names, count.index)}.pem"
    destination = "~/${element(var.kube_worker_node_names, count.index)}.pem"
  }

  provisioner "file" {
    source      = "./tls-certs/kubelet/${element(var.kube_worker_node_names, count.index)}-key.pem"
    destination = "~/${element(var.kube_worker_node_names, count.index)}-key.pem"
  }
}

resource "null_resource" "worker_ca_cert" {
  count = "${length(var.kube_worker_node_names)}"

  depends_on = ["local_file.devo_kube_ca_crt"]
  connection {                                             
    type         = "ssh"                                   
    host = "${element(var.worker_nodes_dns_names,count.index)}"    
    user         = "${var.worker_username}"                       
    password     = "${var.worker_password}"                       
    private_key  = "${file("~/.ssh/kube-devolab_id_rsa")}" 
    timeout      =  "1m"                                   
    agent        = true                                    
  }                                                        
  provisioner "file" {
    source      = "./tls-certs/client-server/ca.pem"
    destination = "~/ca.pem"
  }
}


################################################################################################

# Controller manager certificates : 
# Generate the kube-controller-manager client certificate and private key:
################################################################################################

resource "tls_private_key" "kube_controller_manager" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "tls_cert_request" "kube_controller_manager" {
  key_algorithm   = "${tls_private_key.kube_controller_manager.algorithm}"
  private_key_pem = "${tls_private_key.kube_controller_manager.private_key_pem}"

  subject {
    common_name         = "system:kube-scheduler"
    organization        = "system:kube-scheduler"
    country             = "FR"
    locality            = "Hauts-de-Seine"
    organizational_unit = "Kubernetes The Hard Way"
    province            = "Paris"
  }
}

resource "tls_locally_signed_cert" "kube_controller_manager" {
  cert_request_pem   = "${tls_cert_request.kube_controller_manager.cert_request_pem}"
  ca_key_algorithm   = "${tls_private_key.devo_kube_ca.algorithm}"
  ca_private_key_pem = "${tls_private_key.devo_kube_ca.private_key_pem}"
  ca_cert_pem        = "${tls_self_signed_cert.devo_kube_ca.cert_pem}"

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "cert_signing",
    "client_auth",
    "server_auth",
  ]
}

resource "local_file" "kube_controller_manager_key" {
  content  = "${tls_private_key.kube_controller_manager.private_key_pem}"
  filename = "./tls-certs/controller-manager/kube-controller-manager-key.pem"
}

resource "local_file" "kube_controller_manager_crt" {
  content  = "${tls_locally_signed_cert.kube_controller_manager.cert_pem}"
  filename = "./tls-certs/controller-manager/kube-controller-manager.pem"
}

###############################################################################################
# The Kube Proxy Client Certificate 
# Create the kube-proxy client certificate signing request:
###############################################################################################

resource "tls_private_key" "kube_proxy" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "tls_cert_request" "kube_proxy" {
  key_algorithm   = "${tls_private_key.kube_proxy.algorithm}"
  private_key_pem = "${tls_private_key.kube_proxy.private_key_pem}"

  subject {
    common_name         = "system:kube-proxy"
    organization        = "system:node-proxier"
    country             = "FR"
    locality            = "Hauts-de-Seine"
    organizational_unit = "Kubernetes The Hard Way"
    province            = "Paris"
  }
}

resource "tls_locally_signed_cert" "kube_proxy" {
  cert_request_pem   = "${tls_cert_request.kube_proxy.cert_request_pem}"
  ca_key_algorithm   = "${tls_private_key.devo_kube_ca.algorithm}"
  ca_private_key_pem = "${tls_private_key.devo_kube_ca.private_key_pem}"
  ca_cert_pem        = "${tls_self_signed_cert.devo_kube_ca.cert_pem}"

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "cert_signing",
    "client_auth",
    "server_auth",
  ]
}

resource "local_file" "kube_proxy_key" {
  content  = "${tls_private_key.kube_proxy.private_key_pem}"
  filename = "./tls-certs/kube-proxy/kube-proxy-key.pem"
}

resource "local_file" "kube_proxy_crt" {
  content  = "${tls_locally_signed_cert.kube_proxy.cert_pem}"
  filename = "./tls-certs/kube-proxy/kube-proxy.pem"
}

#########################################################################
# The Scheduler Client Certificate
# Generate the kube-scheduler client certificate and private key:
#########################################################################

resource "tls_private_key" "kube_scheduler" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "tls_cert_request" "kube_scheduler" {
  key_algorithm   = "${tls_private_key.kube_scheduler.algorithm}"
  private_key_pem = "${tls_private_key.kube_scheduler.private_key_pem}"

  subject {
    common_name         = "system:kube-scheduler"
    organization        = "system:kube-scheduler"
    country             = "FR"
    locality            = "Hauts-de-Seine"
    organizational_unit = "Kubernetes The Hard Way"
    province            = "Paris"
  }
}

resource "tls_locally_signed_cert" "kube_scheduler" {
  cert_request_pem   = "${tls_cert_request.kube_scheduler.cert_request_pem}"
  ca_key_algorithm   = "${tls_private_key.devo_kube_ca.algorithm}"
  ca_private_key_pem = "${tls_private_key.devo_kube_ca.private_key_pem}"
  ca_cert_pem        = "${tls_self_signed_cert.devo_kube_ca.cert_pem}"

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "cert_signing",
    "client_auth",
    "server_auth",
  ]
}

resource "local_file" "kube_scheduler_key" {
  content  = "${tls_private_key.kube_scheduler.private_key_pem}"
  filename = "./tls-certs/kube-scheduler/kube-scheduler-key.pem"
}

resource "local_file" "kube_scheduler_crt" {
  content  = "${tls_locally_signed_cert.kube_scheduler.cert_pem}"
  filename = "./tls-certs/kube-scheduler/kube-scheduler.pem"
}

#########################################################################
# The Kubernetes API Server Certificate The kubernetes-the-hard-way static IP address
# will be included in the list of subject alternative names for the Kubernetes API Server certificate. 
# This will ensure the certificate can be validated by remote clients.

# Create the Kubernetes API Server certificate signing request:
##############################################################################

resource "tls_private_key" "kubernetes" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "tls_cert_request" "kubernetes" {
  key_algorithm   = "${tls_private_key.kubernetes.algorithm}"
  private_key_pem = "${tls_private_key.kubernetes.private_key_pem}"

  #ip_addresses = "${concat(var.kubernetes_master_ips, var.apiserver_default_ips, list(data.template_file.public_ip.rendered))}"
  ip_addresses = [
    "10.32.0.1",
    "${var.internal_master_ips}",
    "${var.public_kubernetes_ip}",
    "127.0.0.1",
  ]

  subject {
    common_name         = "kubernetes"
    organization        = "Kubernetes"
    country             = "FR"
    locality            = "Hauts-de-Seine"
    organizational_unit = "Kubernetes The Hard Way"
    province            = "Paris"
  }
}

resource "tls_locally_signed_cert" "kubernetes" {
  cert_request_pem   = "${tls_cert_request.kubernetes.cert_request_pem}"
  ca_key_algorithm   = "${tls_private_key.devo_kube_ca.algorithm}"
  ca_private_key_pem = "${tls_private_key.devo_kube_ca.private_key_pem}"
  ca_cert_pem        = "${tls_self_signed_cert.devo_kube_ca.cert_pem}"

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "cert_signing",
    "client_auth",
    "server_auth",
  ]
}

resource "local_file" "kubernetes_key" {
  content  = "${tls_private_key.kubernetes.private_key_pem}"
  filename = "./tls-certs/kubernetes-key.pem"
}

resource "local_file" "kubernetes_crt" {
  content  = "${tls_locally_signed_cert.kubernetes.cert_pem}"
  filename = "./tls-certs/kubernetes.pem"
}

resource "null_resource" "kubernetes_certs" {
  count = "${var.nodes_count}"
  # "${length(var.master_nodes_dns_names)}"
  depends_on = ["local_file.kubernetes_crt"]
  depends_on = ["local_file.kubernetes_key"]

  connection {                                                   
    type         = "ssh"                                         
    host = "${element(var.master_nodes_dns_names,count.index)}"  
    user         = "${var.api_server_username}"                             
    password     = "${var.api_server_password}"                             
    private_key  = "${file("~/.ssh/kube-devolab_id_rsa")}"       
    timeout      =  "1m"                                         
    agent        = true                                          
  }                                                              
  provisioner "file" {
    source      = "./tls-certs/kubernetes.pem"
    destination = "~/kubernetes.pem"
  }

  provisioner "file" {
    source      = "./tls-certs/kubernetes-key.pem"
    destination = "~/kubernetes-key.pem"
  }
}

##############################################################################
# Service account certs and keys
##############################################################################

## Generate the service-account certificate and private key
/*
provisioner "local-exec" {
  command = "cfssl gencert -ca=tls-certs/client-server/ca.pem -ca-key=tls-certs/client-server/ca-key.pem -config=tls-certs/client-server/ca-config.json -profile=kubernetes t  ls-certs/service-account/service-account-csr.json | cfssljson -bare service-account"
}
*/

resource "tls_private_key" "service-account" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "tls_cert_request" "service-account" {
  key_algorithm   = "${tls_private_key.service-account.algorithm}"
  private_key_pem = "${tls_private_key.service-account.private_key_pem}"

  ip_addresses = [
    "${var.internal_master_ips}",
    "${var.public_kubernetes_ip}",
    "127.0.0.1",
  ]

  subject {
    common_name         = "service-account"
    organization        = "service-account"
    country             = "FR"
    locality            = "Hauts-de-Seine"
    organizational_unit = "service-account The Hard Way"
    province            = "Paris"
  }
}

resource "tls_locally_signed_cert" "service-account" {
  cert_request_pem   = "${tls_cert_request.service-account.cert_request_pem}"
  ca_key_algorithm   = "${tls_private_key.devo_kube_ca.algorithm}"
  ca_private_key_pem = "${tls_private_key.devo_kube_ca.private_key_pem}"
  ca_cert_pem        = "${tls_self_signed_cert.devo_kube_ca.cert_pem}"

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "cert_signing",
    "client_auth",
    "server_auth",
  ]
}

resource "local_file" "service-account_key" {
  content  = "${tls_private_key.service-account.private_key_pem}"
  filename = "./tls-certs/service-account/service-account-key.pem"
}

resource "local_file" "service-account_crt" {
  content  = "${tls_locally_signed_cert.service-account.cert_pem}"
  filename = "./tls-certs/service-account/service-account.pem"
}

resource "null_resource" "service-account_certs" {
  count = "${var.nodes_count}"
  depends_on = ["local_file.service-account_crt"]
  depends_on = ["local_file.service-account_key"]

  connection {                                                   
    type         = "ssh"                                         
    host = "${element(var.master_nodes_dns_names,count.index)}"  
    user         = "${var.api_server_username}"                             
    password     = "${var.api_server_password}"                             
    private_key  = "${file("~/.ssh/kube-devolab_id_rsa")}"       
    timeout      =  "1m"                                         
    agent        = true                                          
  }                                                              
  provisioner "file" {
    source      = "./tls-certs/service-account/service-account.pem"
    destination = "~/service-account.pem"
  }

  provisioner "file" {
    source      = "./tls-certs/service-account/service-account-key.pem"
    destination = "~/service-account-key.pem"
  }
}
