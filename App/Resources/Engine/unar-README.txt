lsar and unar (source tag v1.10.8; the tools report themselves as 1.10.7, an upstream quirk) are bundled, unmodified, from The Unarchiver's
command-line tools, built from source for x86_64 (macOS 13+) on XADMaster.

  Authors:  Dag Agren, MacPaw
  Source:   https://github.com/MacPaw/XADMaster  (tag v1.10.8)
            https://github.com/MacPaw/universal-detector  (tag 1.1)
  License:  GNU Lesser General Public License, version 2.1 or later
            (full text in unar-LICENSE-LGPL-2.1.txt)

They are used only as a fallback for multi-part RAR sets that 7-Zip cannot
open (a 0-byte or missing volume). The corresponding source code is available
at the addresses above; the executables are separate programs launched by
7ZIP4MAC and are not linked into it.
