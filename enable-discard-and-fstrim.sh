sudo awk -v OFS="\t" '{if (($3 == "swap" || $3 == "ext4" || $3 == "xfs" || $3 == "vfat") && !($4 ~ /discard/)) {$4 = ($4 ? $4 "," : "") "discard"} print}' /etc/fstab > /tmp/fstab.tmp && \
sudo mv /tmp/fstab.tmp /etc/fstab && \
echo -e "[Unit]\nDescription=Discard unused blocks once a week\n\n[Service]\nType=oneshot\nExecStart=/sbin/fstrim --all\n\n[Install]\nWantedBy=multi-user.target" | sudo tee /etc/systemd/system/fstrim.service && \
echo -e "[Unit]\nDescription=Run fstrim weekly\n\n[Timer]\nOnCalendar=weekly\nPersistent=true\n\n[Install]\nWantedBy=timers.target\nRandomizedDelaySec=604800" | sudo tee /etc/systemd/system/fstrim.timer && \
sudo systemctl enable fstrim.timer && \
sudo systemctl start fstrim.timer