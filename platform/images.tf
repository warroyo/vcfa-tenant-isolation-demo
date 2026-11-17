# The Ubuntu cloud image the tenant VMs boot from, in an org content library
# attached to every namespace. A VM names it by display name.
#
# The OVA is downloaded once, into .images/ (ignored by git), on the machine
# that first applies this. After that the item is in state and the file is not
# needed.

data "vcfa_org" "org" {
  name = var.vcfa_org
}

data "vcfa_region" "region" {
  name = var.region_name
}

data "vcfa_storage_class" "content_library" {
  region_id = data.vcfa_region.region.id
  name      = var.content_library_storage_policy
}

resource "vcfa_content_library" "images" {
  org_id            = data.vcfa_org.org.id
  name              = "tenant-demo-images"
  description       = "VM images for the tenant isolation demo."
  storage_class_ids = [data.vcfa_storage_class.content_library.id]
  auto_attach       = true
  delete_recursive  = true
}

locals {
  ubuntu_image_file = "${path.module}/.images/${basename(var.ubuntu_image.url)}"
}

resource "terraform_data" "ubuntu_image_download" {
  triggers_replace = [var.ubuntu_image.url]

  provisioner "local-exec" {
    command = "mkdir -p \"$(dirname \"$FILE\")\" && curl -fsSL --retry 3 -o \"$FILE\" \"$URL\""
    environment = {
      FILE = local.ubuntu_image_file
      URL  = var.ubuntu_image.url
    }
  }
}

resource "vcfa_content_library_item" "ubuntu" {
  name               = var.ubuntu_image.name
  description        = "Ubuntu cloud image, from ${var.ubuntu_image.url}."
  content_library_id = vcfa_content_library.images.id
  file_paths         = [local.ubuntu_image_file]

  depends_on = [terraform_data.ubuntu_image_download]
}
