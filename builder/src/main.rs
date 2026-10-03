use std::error::Error;
use std::fs;
use std::io::{self, Write};
use std::path::Path;
use std::process::{Command, Stdio};

type Res<T = ()> = Result<T, Box<dyn Error>>;

const APP: &str = "DynamicIsland.app";
const BIN: &str = ".build/release/DynamicIsland";
const INSTALLED: &str = "/Applications/DynamicIsland.app";

const INFO_PLIST: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>DynamicIsland</string>
	<key>CFBundleDisplayName</key>
	<string>Dynamic Island</string>
	<key>CFBundleIdentifier</key>
	<string>com.niko.dynamicisland</string>
	<key>CFBundleVersion</key>
	<string>1.0</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleExecutable</key>
	<string>DynamicIsland</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSAppleEventsUsageDescription</key>
	<string>Dynamic Island reads the currently playing track from Music and Spotify.</string>
	<key>NSHumanReadableCopyright</key>
	<string>Dynamic Island for Mac</string>
</dict>
</plist>
"#;

fn run(cmd: &str, args: &[&str]) -> Res {
	let status = Command::new(cmd).args(args).status()?;
	if !status.success() {
		return Err(format!("{} failed ({})", cmd, status).into());
	}
	Ok(())
}

fn run_quiet(cmd: &str, args: &[&str]) {
	let _ = Command::new(cmd)
		.args(args)
		.stdout(Stdio::null())
		.stderr(Stdio::null())
		.status();
}

fn ask(promt: &str) -> bool {
	print!("{} [y/N] ", promt);
	io::stdout()
		.flush()
		.ok();
	
	let mut anwser = String::new();
	io::stdin()
    .read_line(&mut anwser)
    .ok();

	matches!(anwser.trim(), "y" | "Y")
}


fn main() -> Res {
	let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
	std::env::set_current_dir(root)?;

	println!("▶︎ Building release binary…");
	run("swift", &["build", "-c", "release"])?;

	println!("▶︎ Building MediaRemote helper dylib…");
	run(
		"clang",
		&[
			"-dynamiclib",
			"-framework",
			"CoreFoundation",
			"-O2",
			"-o",
			".build/mrhelper.dylib",
			"Helpers/mrhelper.c",
		],
	)?;
	run_quiet("codesign", &["--force", "--sign", "-", ".build/mrhelper.dylib"]);

	println!("▶︎ Assembling {APP}…");
	if Path::new(APP).exists() {
		fs::remove_dir_all(APP)?;
	}
	fs::create_dir_all(format!("{APP}/Contents/MacOS"))?;
	fs::create_dir_all(format!("{APP}/Contents/Resources"))?;
	fs::copy(BIN, format!("{APP}/Contents/MacOS/DynamicIsland"))?;
	fs::copy(
		".build/mrhelper.dylib",
		format!("{APP}/Contents/Resources/mrhelper.dylib"),
	)?;
	fs::write(format!("{APP}/Contents/Info.plist"), INFO_PLIST)?;

	run_quiet("codesign", &["--force", "--deep", "--sign", "-", APP]);

	println!("✓ Built {APP}");

	let mut to_open = APP;
	if ask("Do you want to move it to /Applications/?") {
		if Path::new(INSTALLED).exists() {
			fs::remove_dir_all(INSTALLED)?;
		}
		run("ditto", &[APP, INSTALLED])?;
		println!("Moved {APP} to /Applications/");
		to_open = INSTALLED;
	}

	if ask("Do you want to open the app now?") {
		run("open", &[to_open])?;
		println!("Opened {to_open}");
	}

	Ok(())
}
