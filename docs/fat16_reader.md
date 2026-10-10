# FAT16 reader — implementation plan

yasboot reads `/boot` (the `YASBOOT` partition, FAT16, `-F 16` from
`usr/bin/cardreformat` → `mkfs.fat`) to find `/yasboot/*.ybi` update images
(see `docs/bootloader_plan.md` §4.5 in the yasos.zig parent repo). This is a
self-hosted reader, not FatFs/zfat: read-only, one known volume, one known
subdirectory, 8.3 names only. No FAT12/FAT32/exFAT, no writes, no long
filenames, no path resolution beyond `/yasboot/<name>`.

## On-disk pieces needed

1. **MBR** (LBA 0): four 16-byte partition entries at offset `0x1BE`. Find
   the `YASBOOT` partition by type byte (`0x04`/`0x06`/`0x0E`, FAT16/FAT16B)
   and take its start LBA — don't assume partition 1, `cardreformat` numbers
   by table order but a card could be re-laid-out.
2. **BPB** (first sector of the partition): `bytes_per_sector` (expect 512,
   but read it — don't hardcode), `sectors_per_cluster`, `reserved_sectors`,
   `num_fats` (expect 2), `root_entry_count`, `sectors_per_fat` (16-bit field
   at offset 0x16), `total_sectors` (16-bit at 0x13, or 32-bit at 0x20 if
   that's 0). From these:
   ```
   fat_start_lba   = partition_start + reserved_sectors
   root_dir_lba    = fat_start_lba + num_fats * sectors_per_fat
   root_dir_sectors = ceil(root_entry_count * 32 / bytes_per_sector)
   data_start_lba  = root_dir_lba + root_dir_sectors
   cluster_to_lba(n) = data_start_lba + (n - 2) * sectors_per_cluster
   ```
3. **FAT16 table**: array of 16-bit entries at `fat_start_lba`. Cluster `n`'s
   next link is entry `n`; `0xFFF8..0xFFFF` = end of chain, `0xFFF7` = bad
   cluster, `0` = free (shouldn't appear in a live chain).
4. **Directory entries**: 32 bytes each, no subdirectories below one level.
   - Root directory: fixed region (`root_dir_lba`, `root_dir_sectors`), not
     cluster-chained.
   - `/yasboot/`: an entry in the root with attribute bit 0x10 (directory);
     its first-cluster field starts a normal cluster chain, read the same
     way as a file, reinterpreted as more 32-byte entries.
   - Skip entries whose first byte is `0x00` (end) or `0xE5` (deleted), and
     attribute `0x0F` (LFN continuation — must still be skippable even
     though we never generate them, since `mkfs.fat` won't write any but a
     foreign tool touching the card might).
5. **8.3 name match**: uppercase the target, space-pad name to 8 and
   extension to 3, memcmp against entry bytes `0..11`. No case-insensitive
   Unicode table, no OEM codepage handling — this reader only has to match
   names it itself expects to find.

## Reader API (sketch)

```
mount(partition_start_lba) -> Volume          // reads BPB, computes offsets above
find(Volume, "/yasboot/kernel.ybi") -> Entry? // one root scan + one subdir scan
read(Volume, Entry, offset, buf) -> usize     // walk the FAT16 chain, read sectors
```

`find` only ever needs two directory scans (root, then one subdirectory) —
it does not need a general path splitter.

## Explicitly not supported

- FAT12 or FAT32 volumes (mount fails closed rather than guessing).
- Long file names — `/yasboot/*.ybi` names must be valid 8.3. This bites
  `fpga_card.ybi` from the bootloader plan: `FPGA_CARD` is 9 characters,
  over the 8-character limit. Needs renaming (e.g. `fpgacard.ybi` or
  `fpgacrd.ybi`) before that card ships — flagging back into
  `docs/bootloader_plan.md` §4.5.
- Any write path, timestamps, free-space accounting, or multi-partition
  awareness beyond locating the one `YASBOOT` partition.

## Size and testing

Expect a few hundred lines of Zig: BPB/MBR struct parsing, the cluster-chain
walk, and the two-level directory scan are each small and independent.
Compare against the FatFs-based 14–18 KB line item in
`docs/bootloader_plan.md` §7 once it's built — this should land well under
that since it carries none of FatFs's multi-volume/write/LFN machinery.

Test the same way `tests/smoke/mkfs_fat_test.py` and the QEMU fatdisk path
already do: build a small FAT16 image with the in-tree `mkfs.fat -F 16`,
drop known-good and deliberately-malformed images (truncated chain, bad
directory entry, wrong FAT type) on it, and assert the reader finds the
right bytes or fails closed. No real card needed for this layer.

## License and patents

**Copyright/license:** written from the public BPB field layout (the same
facts Wikipedia's "Design of the FAT file system" and Microsoft's own
published FAT32 spec document — the layout, not code, is what's borrowed),
not by copying or adapting FatFs (ChaN, 1-clause BSD-style) or dosfstools
(GPLv2) source. yasboot is GPLv3 (`yasboot/LICENSE`); this file follows the
rest of the tree.

**Patents:** Microsoft holds three FAT-related patents — US 5,579,517
("common name space for long and short filenames"), US 5,758,352, and
US 6,286,013. All three claim the *long-filename compatibility scheme*
(VFAT: storing a long name alongside a generated 8.3 alias so old software
keeps working), not the base FAT12/16 structures, which predate any of them
(MS-DOS 1.0, 1981). This reader never implements LFN, so it falls outside
those claims on scope alone — and all three patents have also now expired
(the longest-lived ran through 2021; it's 2026). exFAT has its own, separate
Microsoft patent-licensing program, irrelevant here since nothing in this
plan touches exFAT. Net: no license or royalty is needed for a FAT16,
short-names-only reader.

Sources: [FAT File System Patent: Legacy and Legal Impact](https://patentpc.com/blog/fat-file-system-patent-legacy-and-legal-impact),
[HN: the patents on FAT32 are now fully expired](https://news.ycombinator.com/item?id=25633899),
[VFAT patent avoidance and patent workarounds (LWN)](https://lwn.net/Articles/338981/),
[Design of the FAT file system (Wikipedia)](https://en.wikipedia.org/wiki/Design_of_the_FAT_file_system).
