packer {
  required_plugins {
    arm-image = {
      version = "0.2.5"
      source  = "github.com/solo-io/arm-image"
    }
  }
}

variable "branch" {
  type    = string
  default = "master"
}

source "arm-image" "companionpi" {
  iso_checksum              = "sha256:c88109027eac44b9ff37a7f3eb1873cdf6d7ca61a0264ec0e95870ca96afd242"
  iso_url                   = "https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2021-11-08/2021-10-30-raspios-bullseye-arm64-lite.zip"
  last_partition_extra_size = 4294967296
  qemu_binary               = "qemu-aarch64-static"
}

build {
  sources = ["source.arm-image.companionpi"]

  provisioner "shell" {
    #system setup
    inline = [
      # enable ssh
      "touch /boot/ssh",

      # change the hostname
      "CURRENT_HOSTNAME=`cat /etc/hostname | tr -d \" \t\n\r\"`",
      "echo CompanionPi > /etc/hostname",
      "sed -i \"s/127.0.1.1.*$CURRENT_HOSTNAME/127.0.1.1\tCompanionPi/g\" /etc/hosts",

      # add a system user
      "adduser --disabled-password companion --gecos \"\"",

      # change the local to en-us
      "echo \"en_US.UTF-8 UTF-8\" | tee -a /etc/locale.gen",
      "locale-gen",

      # install some dependencies
      "apt-get update",
      "apt-get install -y git unzip curl libusb-1.0-0-dev libudev-dev",
      "apt-get clean"
    ]
  }

  provisioner "shell" {
    # run as root
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} su root -c {{ .Path }}"
    inline_shebang  = "/bin/bash -e"
    inline = [
      # install fnm to manage node version
      # we do this to /opt/fnm, so that the companion user can use the same installation
      "export FNM_DIR=/opt/fnm",
      "echo \"export FNM_DIR=/opt/fnm\" >> /root/.bashrc",
      "curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir /opt/fnm",
      "export PATH=/opt/fnm:$PATH",
      "eval \"`fnm env --shell bash`\"",
      # clone the repository
      "git clone https://github.com/bitfocus/companion.git -b ${var.branch} /usr/local/src/companion",
      "cd /usr/local/src/companion",
      # configure git for future updates
      "git config --global pull.rebase false",
      # run the update script
      "./tools/companionpi/update.sh ${var.branch}",
      # enable start on boot
      "systemctl enable companion"
    ]
  }

  provisioner "shell" {
    # run as companion user
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} su companion -c {{ .Path }}"
    inline_shebang  = "/bin/bash -e"
    inline = [
      "cd /usr/local/src/companion",

      # add the fnm node to this users path
      "echo \"export PATH=/opt/fnm/aliases/default/bin:\\$PATH\" >> ~/.bashrc"

    ]
  }

}
