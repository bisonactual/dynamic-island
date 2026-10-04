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
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
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

/// Whether to embed the custom app icon. The `DI_ICON` env var wins so the choice
/// can be made permanent without being prompted — set it in `.cargo/config.toml`'s
/// `[env]` section (DI_ICON = "1" to always add it, "0" to always skip). When unset
/// (or anything else), it asks interactively.
fn want_icon() -> bool {
	match std::env::var("DI_ICON").unwrap_or_default().to_lowercase().as_str() {
		"1" | "true" | "yes" | "always" => true,
		"0" | "false" | "no" | "never" => false,
		_ => ask("Use the custom app icon?"),
	}
}

fn build_icon(resources_dir: &str) -> Res {
	if !want_icon() {
		return Ok(());
	}

	let svg = "Assets/AppIcon.svg";
	if !Path::new(svg).exists() {
		eprintln!("⚠︎ {svg} not found; skipping app icon");
		return Ok(());
	}

	println!("▶︎ Building app icon…");
	let work = ".build/iconwork";
	let iconset = ".build/AppIcon.iconset";
	let _ = fs::remove_dir_all(work);
	let _ = fs::remove_dir_all(iconset);
	fs::create_dir_all(work)?;
	fs::create_dir_all(iconset)?;

	run_quiet("qlmanage", &["-t", "-s", "1024", "-o", work, svg]);
	let master = format!("{work}/AppIcon.svg.png");
	if !Path::new(&master).exists() {
		eprintln!("⚠︎ could not rasterize {svg}; skipping app icon");
		return Ok(());
	}

	let sizes: [(u32, &str); 10] = [
		(16, "icon_16x16.png"),    (32, "icon_16x16@2x.png"),
		(32, "icon_32x32.png"),    (64, "icon_32x32@2x.png"),
		(128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
		(256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
		(512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
	];
	for (px, name) in sizes {
		let px = px.to_string();
		run_quiet("sips", &["-z", &px, &px, &master, "--out", &format!("{iconset}/{name}")]);
	}

	// Pack into .icns — but never fail the whole build over the icon.
	let icns = format!("{resources_dir}/AppIcon.icns");
	run_quiet("iconutil", &["-c", "icns", iconset, "-o", &icns]);
	if !Path::new(&icns).exists() {
		eprintln!("⚠︎ could not build AppIcon.icns; the app will use the default icon");
	}
	Ok(())
}

fn ask(prompt: &str) -> bool {
	print!("{} [y/N] ", prompt);
	io::stdout().flush().ok();

	let mut answer = String::new();
	io::stdin().read_line(&mut answer).ok();

	matches!(answer.trim(), "y" | "Y")
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

	build_icon(&format!("{APP}/Contents/Resources"))?;

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
