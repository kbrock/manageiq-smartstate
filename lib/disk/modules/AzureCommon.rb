require_relative '../MiqDisk'
require 'ostruct'

module AzureCommon
  # The maximum read length that supports MD5 return.
  MAX_READ_LEN  = 1024 * 1024 * 4
  SECTOR_LENGTH = 512

  def self.d_init_common(dInfo)
    @blockSize        = SECTOR_LENGTH
    @blob_uri         = dInfo.blob_uri if dInfo.blob_uri
    @disk_name        = dInfo.disk_name if dInfo.disk_name
    @storage_acct_svc = dInfo.storage_acct_svc if dInfo.storage_acct_svc
    @storage_disk_svc = dInfo.storage_disk_svc if dInfo.storage_disk_svc
    @resource_group   = dInfo.resource_group if dInfo.resource_group

    if @storage_acct_svc
      @my_class     = "AzureBlobDisk"
      uri_info      = @storage_acct_svc.parse_uri(@blob_uri)
      @container    = uri_info[:container]
      @blob         = uri_info[:blob]
      @acct_name    = uri_info[:account_name]
      @snapshot     = uri_info[:snapshot]
      @storage_acct = @storage_acct_svc.accounts_by_name[@acct_name]
      @disk_path    = @blob_uri
      raise "AzureBlob: Storage account #{@acct_name} not found." unless @storage_acct
    else
      @disk_path = @disk_name
      @my_class     = "AzureManagedDisk"
    end
    $log.debug "#{@class}: open(#{@disk_path})"

    @t0 = Time.now.to_i
    @reads = 0
    @bytes = 0
    @split_reads = 0
  end

  def self.d_close_common
    return nil unless $log.debug?
    t1 = Time.now.to_i
    $log.debug "#{@my_class}: close(#{@disk_path})"
    $log.debug "#{@my_class}: (#{@disk_path}) time:  #{t1 - @t0}"
    $log.debug "#{@my_class}: (#{@disk_path}) reads: #{@reads}, split_reads: #{@split_reads}"
    $log.debug "#{@my_class}: (#{@disk_path}) bytes: #{@bytes}"
    nil
  end

  def self.d_read_common(pos, len)
    return blob_read(pos, len) unless len > MAX_READ_LEN

    @split_reads += 1
    ret = ""
    blocks, rem = len.divmod(MAX_READ_LEN)

    blocks.times do
      ret << blob_read(pos, MAX_READ_LEN)
    end
    ret << blob_read(pos, rem) if rem > 0

    ret
  end

  def self.blob_properties
    @blob_properties ||= begin
      options = @snapshot ? {:date => @snapshot} : {}
      @storage_acct.blob_properties(@container, @blob, key, options)
    end
  end

  private

  def self.blob_read(start_byte, length)
    $log.debug "#{@my_class}#blob_read(#{start_byte}, #{length})"
    options = {
      :start_byte => start_byte,
      :length     => length
    }
    if @storage_acct
      options[:date] = @snapshot if @snapshot
      ret = @storage_acct.get_blob_raw(@container, @blob, key, options)
    else
      ret = @storage_disk_svc.get_blob_raw(@disk_name, @resource_group, options)
    end

    @reads += 1
    @bytes += ret.body.length

    ret.body
  end

  def self.key
    @key ||= @storage_acct_svc.list_account_keys(@storage_acct.name, @storage_acct.resource_group).fetch('key1')
  end
end
