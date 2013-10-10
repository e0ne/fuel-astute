#    Copyright 2013 Mirantis, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.


require "json"
require "base64"
require 'fileutils'

module MCollective
  module Agent
    class Erase_node<RPC::Agent
      action "erase_node" do
        erase_node
      end

      action "reboot_node" do
        reboot
      end

    private

      def erase_node
        request_reboot = request.data[:reboot]
        dry_run = request.data[:dry_run]
        error_msg = []
        reply[:status] = 0  # Shell exitcode behaviour

        prevent_discover unless dry_run

        begin
          get_boot_devices.each do |dev|
            erase_data(dev) unless dry_run
          end
          reply[:erased] = true
        rescue Exception => e
          reply[:erased] = false
          reply[:status] += 1
          msg = "MBR can't be erased. Reason: #{e.message};"
          Log.error(msg)
          error_msg << msg
        end

        begin
          reboot if not dry_run and request_reboot
          reply[:rebooted] = true
        rescue Exception => e
          reply[:rebooted] = false
          reply[:status] += 1
          msg = "Can't reboot node. Reason: #{e.message};"
          Log.error(msg)
          error_msg << "Can't reboot node. Reason: #{e.message};"
        end

        unless error_msg.empty?
          reply[:error_msg] = error_msg.join(' ')
        end
      end

      def get_boot_devices
        raise "Path /sys/block does not exist" unless File.exists?("/sys/block")
        Dir["/sys/block/*"].inject([]) do |blocks, block_device_dir|
          basename_dir = File.basename(block_device_dir)
          major = `udevadm info --query=property --name=#{basename_dir} | grep MAJOR`.strip.split(/\=/)[-1]
          if File.exists?("/sys/block/#{basename_dir}/removable")
            removable = File.open("/sys/block/#{basename_dir}/removable"){|f| f.read_nonblock(1024).strip}
          end
          blocks << basename_dir if major =~ /^(8|3)$/ && removable =~ /^0$/
        end
      end

      def get_boot_device_obsolete
        dev_map = '/boot/grub/device.map'
        grub_conf = '/boot/grub/grub.conf'
        # Look boot device at GRUB device.map file
        if File.file?(dev_map) and File.readable?(dev_map)
          open(dev_map).readlines.each do |l|
            line = l.strip
            unless line.start_with?('#')
              grub_dev, kernel_dev = line.split(%r{[ |\t]+})
              return kernel_dev if grub_dev == '(hd0)'
            end
          end
        end
        # Look boot device at GRUB config autogenerated file
        if File.file?(grub_conf) and File.readable?(grub_conf)
          open(grub_conf).readlines.each do |l|
            line = l.strip
            if line.start_with?('#boot=')
              grub_dev, kernel_dev = line.split('=')
              return kernel_dev
            end
          end
        end
        # If nothing found
        raise 'Boot device not found.'
      end

      def reboot
        cmd = "/bin/sleep 5; /sbin/reboot --force"
        pid = fork { system(cmd) }
        Process.detach(pid)
      end

      def get_data(file, length, offset=0)
        fd = open(file)
        fd.seek(offset)
        ret = fd.sysread(length)
        fd.close
        ret
      end

      def erase_data(dev, length=1, offset=0)
        system("dd if=/dev/zero of=/dev/#{dev} bs=1M count=#{length} skip=#{offset}")
      end

      def erase_data_obsolete(file, length, offset=0)
        fd = open(file, 'w')
        fd.seek(offset)
        ret = fd.syswrite("\000"*length)
        fd.close
        system('/bin/sync')
      end

      # Prevent discover by agent while node rebooting.
      def prevent_discover
        FileUtils.touch '/var/run/nodiscover'
      end
    end
  end
end
