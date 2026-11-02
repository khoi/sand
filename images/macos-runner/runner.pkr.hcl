variable "host" {
  type = string
}

variable "ssh_username" {
  type    = string
  default = "lume"
}

variable "ssh_password" {
  type      = string
  default   = "lume"
  sensitive = true
}

variable "xcode_apps" {
  type = list(string)
}

source "null" "lume" {
  communicator = "ssh"
  ssh_host     = var.host
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "15m"
}

build {
  sources = ["source.null.lume"]

  provisioner "shell" {
    inline = [
      "echo '${var.ssh_username} ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/${var.ssh_username}",
      "chmod 0440 /etc/sudoers.d/${var.ssh_username}",
    ]
    execute_command = "chmod +x {{ .Path }}; echo '${var.ssh_password}' | sudo -S {{ .Vars }} {{ .Path }}"
  }

  provisioner "shell" {
    script          = "scripts/system.sh"
    execute_command = "chmod +x {{ .Path }}; sudo {{ .Vars }} {{ .Path }}"
  }

  provisioner "shell" {
    script = "scripts/user.sh"
  }

  provisioner "shell" {
    environment_vars = ["XCODE_APPS=${join(" ", var.xcode_apps)}"]
    script           = "scripts/xcode.sh"
  }

  provisioner "shell" {
    inline            = ["sudo shutdown -h now"]
    expect_disconnect = true
    skip_clean        = true
  }
}
