set server_path [tmpdir "server.rdb-encoding-test"]

# Copy RDB with different encodings in server path
exec cp tests/assets/encodings.rdb $server_path

start_server [list overrides [list "dir" $server_path "dbfilename" "encodings.rdb"]] {
  test "RDB encoding loading test" {
    r select 0
    csvdump r
  } {"compressible","string","aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
"hash","hash","a","1","aa","10","aaa","100","b","2","bb","20","bbb","200","c","3","cc","30","ccc","300","ddd","400","eee","5000000000",
"hash_zipped","hash","a","1","b","2","c","3",
"list","list","1","2","3","a","b","c","100000","6000000000","1","2","3","a","b","c","100000","6000000000","1","2","3","a","b","c","100000","6000000000",
"list_zipped","list","1","2","3","a","b","c","100000","6000000000",
"number","string","10"
"set","set","1","100000","2","3","6000000000","a","b","c",
"set_zipped_1","set","1","2","3","4",
"set_zipped_2","set","100000","200000","300000","400000",
"set_zipped_3","set","1000000000","2000000000","3000000000","4000000000","5000000000","6000000000",
"string","string","Hello World"
"zset","zset","a","1","b","2","c","3","aa","10","bb","20","cc","30","aaa","100","bbb","200","ccc","300","aaaa","1000","cccc","123456789","bbbb","5000000000",
"zset_zipped","zset","a","1","b","2","c","3",
}
}

set server_path [tmpdir "server.rdb-startup-test"]

start_server [list overrides [list "dir" $server_path]] {
    test {Server started empty with non-existing RDB file} {
        r debug digest
    } {0000000000000000000000000000000000000000}
    # Save an RDB file, needed for the next test.
    r save
}

start_server [list overrides [list "dir" $server_path]] {
    test {Server started empty with empty RDB file} {
        r debug digest
    } {0000000000000000000000000000000000000000}
}

# Helper function to start a server and kill it, just to check the error
# logged.
set defaults {}
proc start_server_and_kill_it {overrides code} {
    upvar defaults defaults srv srv server_path server_path
    set config [concat $defaults $overrides]
    set srv [start_server [list overrides $config]]
    uplevel 1 $code
    kill_server $srv
}

if { $::tcl_platform(platform) != "windows" } {
# Make the RDB file unreadable
file attributes [file join $server_path dump.rdb] -permissions 0222

# Now make sure the server aborted with an error
start_server_and_kill_it [list "dir" $server_path] {
    wait_for_condition 50 100 {
        [string match {*Fatal error loading*} \
            [exec tail -n1 < [dict get $srv stdout]]]
    } else {
        fail "Server started even if RDB was unreadable!"
    }
}

# Fix permissions of the RDB file, but corrupt its CRC64 checksum.
file attributes [file join $server_path dump.rdb] -permissions 0666
set filesize [file size [file join $server_path dump.rdb]]
set fd [open [file join $server_path dump.rdb] r+]
fconfigure $fd -translation binary
seek $fd -8 end
puts -nonewline $fd "foobar00"; # Corrupt the checksum
close $fd

# Now make sure the server aborted with an error
start_server_and_kill_it [list "dir" $server_path] {
    wait_for_condition 50 100 {
        [string match {*RDB checksum*} \
            [exec tail -n1 < [dict get $srv stdout]]]
    } else {
        fail "Server started even if RDB was corrupted!"
    }
}
}