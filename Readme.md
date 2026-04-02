# VMFS Reclaim

When VMFS automatic UNMAP became a thing with VMFS6, it did work well but with caveats. Some SANs have quite large allocation blocks, in this case Hitachi has 42MB.

So when thin VMDK shrunk slowly in 1MB increments, it did not properly reclaim space as you had to free the whole 42MB block at once. Over time this caused quite a lot of dead space on SAN (IIRC ~10% difference between VMFS free and LUN host written space). Even Hitachi lying about having 256K allocation would not fix it (when automatic UNMAP required <=1MB UNMAP blocks).

So I wrote this snippet (plus a function I took from referenced link) to manually UNMAP one datastore/LUN per day (too many UNMAPs would kill array performance). And voila, you have more free space on SAN. Might still be the case on arrays that have internal allocation block over 1MB. Dothill based stuff comes to mind (HPE MSA, Dell MD), IIRC they had 4MB block.

# In-VM Linux Reclaim

The second script is oneliner to add discard flag to each supported filesystem in fstab. Note that even swap is supported for discard. It also recreates/enables fstrim timer with more randomless to spread out the load of batch discards. I think you could effectively run it on every boot/shutdown. Or maybe attach it to fstab with inotify so you would always get discard flag applied, before mounting the filesystem.

Note the for efficient operation, you need both discard and timer. On thin filesystems (think virtualization or storage arrays), your block device has larger UNMAP/TRIM/Deallocate granularity and alignment (for example 1M) than filesystem (usually 4k).

Imagine a case of deleting a single 4k file. As block device has larger granularity and alignment, nothing is done, effectively leaving lost thin space. However, when over week you have deleted enough 4k files to free the whole 1M block, timer can still free it.

In case you deleted a 1M file (with correct alignement!), you just get thin space back immediately.

Larger block size and alignment requirements are also the reason why defragmentation is sometimes pretty effective on thin provisioned disks - you can return the thin allocated space that would otherwise be stuck.

Note that on Linux, LVM-LUKS-dmcrypt or whatever volume manager of filter in path you use, must also support passing on discards. So make sure that your config there as issue_discards or allow_discards or anything similar set to 1/true.

Also note that effectively (not entirely true, but true enough), thin provisioned property of disks is only discovered on VM boot. So if you had thick VM disk on VM boot and converted it to thin, reboot your VM or discards will not work (especially true with LVM).