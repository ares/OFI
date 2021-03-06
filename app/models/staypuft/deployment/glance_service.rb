module Staypuft
  class Deployment::GlanceService < Deployment::AbstractParamScope
    def self.param_scope
      'glance'
    end

    NFS_HELP = N_('(<server>:<local path>)')
    BACKEND_FILE = 'file'
    BACKEND_RBD  = 'rbd'

    param_attr :driver_backend, :nfs_network_path

    module DriverBackend
      LOCAL   = 'local'
      NFS     = 'nfs'
      CEPH    = 'ceph'
      LABELS  = { LOCAL   => N_('Local File'),
                  NFS     => N_('NFS'),
                  CEPH    => N_('Ceph') }
      TYPES   = LABELS.keys
      HUMAN   = N_('Choose Driver Backend')
    end

    validates :driver_backend, presence: true, inclusion: { in: lambda {|g| g.backend_types_for_layout } }

    module NfsNetworkPath
      HUMAN       = N_('network path')
      HUMAN_AFTER = NFS_HELP
    end

    validates :nfs_network_path,
              :presence => true,
              :if       => :nfs_backend?
    # TODO: network_path validation

    class Jail < Safemode::Jail
      allow :driver_backend, :pcmk_fs_type, :pcmk_fs_device, :pcmk_fs_options, :backend,
            :pcmk_fs_manage
    end

    def set_defaults
      self.driver_backend = DriverBackend::LOCAL
    end

    # glance config always shows up
    def active?
      true
    end

    def local_backend?
      self.driver_backend == DriverBackend::LOCAL
    end

    def nfs_backend?
      self.driver_backend == DriverBackend::NFS
    end

    def ceph_backend?
      self.driver_backend == DriverBackend::CEPH
    end

    def backend
      ceph_backend? ? BACKEND_RBD : BACKEND_FILE
    end

    def pcmk_fs_type
      if self.nfs_backend?
        self.driver_backend
      end
    end

    def pcmk_fs_device
      if self.nfs_backend?
        self.nfs_network_path
      end
    end

    def pcmk_fs_options
      if self.nfs_backend?
        'nosharecache,context=\"system_u:object_r:glance_var_lib_t:s0\"'
      else
        ''
      end
    end

    def pcmk_fs_manage
      backend == BACKEND_FILE
    end

    # view should use this rather than DriverBackend::LABELS to hide LOCAL for HA.
    def backend_labels_for_layout
      ret_list = DriverBackend::LABELS.clone
      ret_list.delete(DriverBackend::LOCAL) if self.deployment.ha?
      ret_list.delete(DriverBackend::NFS)   if self.deployment.non_ha?
      ret_list
    end

    def backend_types_for_layout
      ret_list = DriverBackend::TYPES.clone
      ret_list.delete(DriverBackend::LOCAL) if self.deployment.ha?
      ret_list.delete(DriverBackend::NFS)   if self.deployment.non_ha?
      ret_list
    end

    def param_hash
      { "driver_backend" => driver_backend, "nfs_network_path" => nfs_network_path}
    end

  end
end
