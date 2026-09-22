# install_drawkit.rb 가 실제로 폴더를 찾아 파일을 쓰고 로드하는지 검사한다.
#   ruby tools/sketchup/test/test_installer.rb
require_relative "su_stub"
require "tmpdir"
require "fileutils"

INSTALLER = File.expand_path("../install_drawkit.rb", __dir__)
$fails = 0

def title(t); puts "\n=== #{t} ==="; end
def check(label, cond)
  puts((cond ? "  [OK]   " : "  [FAIL] ") + label)
  $fails += 1 unless cond
  cond
end

# 설치 스크립트를 깨끗한 상태에서 1회 실행한다.
def run_installer(appdata: nil, home: nil, load_paths: [], support_file: nil)
  ENV["APPDATA"] = appdata
  ENV["HOME"] = home
  old_lp = $LOAD_PATH.dup
  $LOAD_PATH.concat(load_paths)
  Sketchup.set_support_file("Plugins", support_file)
  Object.send(:remove_const, :DrawKit) if defined?(DrawKit)
  Object.send(:remove_const, :DRAWKIT_SOURCE) if defined?(DRAWKIT_SOURCE)
  out = ""
  begin
    require "stringio"
    buf = StringIO.new
    orig = $stdout
    $stdout = buf
    load INSTALLER
    $stdout = orig
    out = buf.string
  ensure
    $stdout = STDOUT
    $LOAD_PATH.replace(old_lp)
  end
  out
end

Dir.mktmpdir do |tmp|
  # ------------------------------------------------------------ 1
  title "1. Plugins 폴더가 아직 없을 때 (Windows 가정) — 스스로 만들어 설치"
  appdata = File.join(tmp, "AppData/Roaming")
  FileUtils.mkdir_p(appdata)
  out = run_installer(appdata: appdata, home: nil)
  expected = File.join(appdata, "SketchUp/SketchUp 2023/SketchUp/Plugins/drawkit.rb")
  check("표준 경로에 설치됨", File.exist?(expected))
  check("DrawKit 로드됨", defined?(DrawKit) ? true : false)
  check("설치 완료 메시지 출력", out.include?("설치 완료"))
  check("원본과 내용 동일", File.read(expected) == File.read(File.expand_path("../drawkit.rb", __dir__)))

  # ------------------------------------------------------------ 2
  title "2. 이미 쓰기 가능한 Plugins 폴더가 있을 때 — 그쪽에 설치"
  existing = File.join(tmp, "SketchUp 2023/SketchUp/Plugins")
  FileUtils.mkdir_p(existing)
  run_installer(appdata: appdata, home: nil, load_paths: [existing])
  check("$LOAD_PATH 의 Plugins 폴더 우선", File.exist?(File.join(existing, "drawkit.rb")))

  # ------------------------------------------------------------ 3
  title "3. 쓸 수 없는 경로는 건너뛰고 대체 위치에 설치하는가"
  # 참고: 이 컨테이너는 root 로 돌아 퍼미션 비트(0555)를 무시하므로,
  #       '쓸 수 없음' 을 부모가 일반 파일인 경로(ENOTDIR)로 재현한다.
  blocker = File.join(tmp, "blocker_file")
  File.write(blocker, "not a directory")
  unwritable = File.join(blocker, "SketchUp/Plugins")
  appdata2 = File.join(tmp, "AppData2/Roaming")
  FileUtils.mkdir_p(appdata2)
  out3 = run_installer(appdata: appdata2, home: nil, support_file: unwritable, load_paths: [unwritable])
  check("쓸 수 없는 경로에 설치하지 않음", !File.exist?(File.join(unwritable, "drawkit.rb")))
  check("쓰기 가능한 곳으로 대체 설치", File.exist?(File.join(appdata2, "SketchUp/SketchUp 2023/SketchUp/Plugins/drawkit.rb")))
  check("예외로 중단되지 않고 완료", out3.include?("설치 완료"))

  # ------------------------------------------------------------ 4
  title "4. macOS 가정 (APPDATA 없음, HOME 만 존재)"
  home = File.join(tmp, "Users/daain")
  FileUtils.mkdir_p(home)
  run_installer(appdata: nil, home: home)
  mac_path = File.join(home, "Library/Application Support/SketchUp 2023/SketchUp/Plugins/drawkit.rb")
  check("macOS 표준 경로에 설치됨", File.exist?(mac_path))

  # ------------------------------------------------------------ 5
  title "5. 설치 직후 바로 모델링이 되는가 (재시작 없이)"
  Sketchup.reset_model!
  bad = DrawKit.build("설치 확인") do
    box "TEST-1", 0, 0, 0, 1000, 1000, 1000
  end
  check("build 실행 및 검증 통과", bad.empty?)
end

puts "\n" + "=" * 60
puts $fails.zero? ? "전체 통과" : "실패 #{$fails}건"
exit($fails.zero? ? 0 : 1)
