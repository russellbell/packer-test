packer {
  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = "~> 1"
    }
  }
}

variable "cpus" {
  type    = string
  default = "2"
}

variable "disk_size" {
  type    = string
  default = "262144"
}

variable "headless" {
  type    = string
  default = "false"
}

variable "iso_checksum" {
  type    = string
  default = "3D4D388D6FFA371956304FA7401347B4535FD10E3137978A8F7750B790A43521"
}

variable "iso_url" {
  type    = string
  default = "./iso/Windows_11.iso"
}

variable "memory" {
  type    = string
  default = "4096"
}

variable "vm_name" {
  type    = string
  default = "windows_11"
}


source "virtualbox-iso" "virtualbox" {
  boot_command = ["a<wait>a<wait>a<wait>a<wait>a<wait>a"]
  boot_wait    = "-1s"
  cd_files = [
    "./answer_files/11_hyperv/Autounattend.xml",
    "./scripts/disable-winrm.ps1",
    "./scripts/enable-winrm.ps1"
  ]
  communicator         = "winrm"
  cpus                 = "${var.cpus}"
  disk_size            = "${var.disk_size}"
  firmware             = "efi"
  guest_additions_mode = "disable"
  guest_os_type        = "Windows11_64"
  headless             = "${var.headless}"
  iso_checksum         = "${var.hash}"
  iso_url              = "${var.urlPath}"
  memory               = "${var.memory}"
  shutdown_command     = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer Shutdown\""
  vm_name              = "${var.vm_name}"
  winrm_password       = "ChangeMe123!"
  winrm_timeout        = "6h"
  winrm_username       = "workspaces_byol"
}


build {
  sources = ["sources.virtualbox-iso.virtualbox"]

  provisioner "file" {
    source      = "./scripts/BYOLChecker"
    destination = "C:/Users/workspaces_byol/Documents"
  }

  provisioner "powershell" {
    scripts = [
      "./scripts/cleanUp.ps1"
    ]
  }

}
