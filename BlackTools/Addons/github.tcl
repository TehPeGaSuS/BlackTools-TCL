package require tls
package require http
::http::register https 443 ::tls::socket

namespace eval ::github {
    variable libdir [file normalize [file join [file dirname [info script]] ..]]
    if {[lsearch $::auto_path $libdir] == -1} {
        lappend auto_path $libdir
    }
}

package provide github::github 0.4
package provide github 0.4

# Main procedure to download GitHub repository as a .tar.gz archive
# (branch "" = the default branch of the repository)
proc ::github::github {cmd owner repo folder {branch ""}} {
    variable libdir
    set url https://api.github.com/repos/$owner/$repo/tarball
    if {$branch ne ""} {append url /$branch}
    download_archive $url $folder
}

# Background download with wget
proc ::github::download_archive {url folder} {
    # Create the folder if it doesn't exist
    if {![file exists $folder]} {
        file mkdir $folder
    }

    # Define the path for the downloaded archive
    set archive_path [file join $folder "bt.tar.gz"]

    # Run the wget command in the background
    # It is saved as .part and renamed only when curl succeeded, so the check below
    # never unpacks a half-downloaded archive (or an error page).
    set command [list sh -c "curl -fsSL -o '$archive_path.part' '$url' && mv '$archive_path.part' '$archive_path' || rm -f '$archive_path.part' >/dev/null 2>&1 &"]

    if {[catch {exec {*}$command} errMsg]} {
        putlog "\[BT\] - AutoUpdate - Error: Failed to start download $url in background"
        putlog "\[BT\] - AutoUpdate - Details: $errMsg"
        return
    }

    # Check periodically if download is complete
    utimer 5 [list ::github::check_download_complete $archive_path $folder]
}

# Periodically check if the download is complete
proc ::github::check_download_complete {archive_path folder {tries 0}} {
    # If the download is complete, proceed with extraction
    if {[file exists $archive_path] && [file size $archive_path] > 0} {
        if {[catch {::github::unpack_archive $archive_path $folder} errMsg]} {
            putlog "\[BT\] - AutoUpdate - Error: Failed to unpack archive $archive_path"
            putlog "\[BT\] - AutoUpdate - Details: $errMsg"
        } else {
            putlog "\[BT\] - AutoUpdate - Successfully unpacked archive to $folder"
        }

        # Clean up the archive file after extraction
        file delete $archive_path
    } else {
        # Re-check in 5 seconds if download isn't complete
        if {$tries >= 120} {
            putlog "\[BT\] - AutoUpdate - Error: the download of the update did not finish (gave up after 10 minutes)"
            return
        }
        utimer 5 [list ::github::check_download_complete $archive_path $folder [expr {$tries + 1}]]
    }
}

# Unpack the .tar.gz archive into the specified folder
proc ::github::unpack_archive {archive_path folder} {
    # Define a temporary folder for unpacking
    set temp_folder [file join $folder "temp_unpack"]

    # Ensure the temporary folder exists
    if {![file exists $temp_folder]} {
        file mkdir $temp_folder
    }

    # Extract the tarball into the temporary folder
    if {[catch {exec tar -xzf $archive_path -C $temp_folder} errMsg]} {
        putlog "\[BT\] - AutoUpdate - Error: Failed to extract $archive_path"
        putlog "\[BT\] - AutoUpdate - Details: $errMsg"
        return
    }

    # Locate the first directory inside temp_unpack (e.g., "owner-repo-branch")
    set extracted_dir [lindex [glob -directory $temp_folder *] 0]

    # Move contents from the extracted directory to the target folder
    foreach item [glob -directory $extracted_dir *] {
        file rename -force $item $folder/
    }

    # Clean up the temporary folder and extracted directory
    file delete -force $temp_folder
}
