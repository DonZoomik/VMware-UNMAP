sudo awk -v OFS="\t" '{if (($3 ~ /^(swap|ext2|ext3|ext4|xfs|btrfs|f2fs|vfat|exfat|ntfs)$/) && !($4 ~ /discard/)) {$4 = ($4 ? $4 "," : "") "discard"} print}' /etc/fstab > /tmp/fstab.tmp && \
sudo mv /tmp/fstab.tmp /etc/fstab && \
echo -e "[Unit]\nDescription=Discard unused blocks once a week\n\n[Service]\nType=oneshot\nExecStart=/sbin/fstrim --all\n\n[Install]\nWantedBy=multi-user.target" | sudo tee /etc/systemd/system/fstrim.service && \
echo -e "[Unit]\nDescription=Run fstrim weekly\n\n[Timer]\nOnCalendar=weekly\nPersistent=true\nRandomizedDelaySec=1w\n\n[Install]\nWantedBy=timers.target" | sudo tee /etc/systemd/system/fstrim.timer && \
sudo systemctl enable --now fstrim.timer