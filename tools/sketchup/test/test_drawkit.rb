# drawkit.rb 드라이런 테스트 (SketchUp 없이 실행)
#   ruby tools/sketchup/test/test_drawkit.rb
require_relative "su_stub"
load File.expand_path("../drawkit.rb", __dir__)

$fails = 0
def title(t); puts "\n=== #{t} ==="; end
def check(label, cond)
  puts((cond ? "  [OK]   " : "  [FAIL] ") + label)
  $fails += 1 unless cond
  cond
end

# ---------------------------------------------------------------- 1
title "1. 기본 생성 + 자동 검증 (치수표를 따로 안 적어도 되는가)"
Sketchup.reset_model!
bad = DrawKit.build("1층 골조") do
  box "C1-1", 0,    0, 0,    500,  500,  3000
  box "C1-2", 5000, 0, 0,    500,  500,  3000
  box "G1-1", 500,  0, 2400, 4500, 400,  600
  box "S-1",  0,    0, 3000, 5500, 3000, 150
end
check("4개 부재 자동 검증 통과 (EXPECTED 배열 불필요)", bad.empty?)

# ---------------------------------------------------------------- 2
title "2. group 중첩"
Sketchup.reset_model!
bad = DrawKit.build("중첩") do
  group "STR-1층" do
    box "C2-1", 0,   0, 0,    400,  400, 2800
    box "G2-1", 400, 0, 2300, 3000, 300, 500
  end
end
check("assembly 하위 부재 검증 통과", bad.empty?)
check("최상위+하위 그룹 3개 존재", DrawKit.rows.size == 3)

# ---------------------------------------------------------------- 3
title "3. 부재명 중복은 생성 전에 차단"
Sketchup.reset_model!
blocked = false
begin
  DrawKit.build("중복") do
    box "C1", 0,    0, 0, 400, 400, 2800
    box "C1", 5000, 0, 0, 400, 400, 2800
  end
rescue ArgumentError => e
  blocked = true
  puts "  차단 메시지: #{e.message}"
end
check("중복 이름 차단됨", blocked)
check("롤백되어 그룹 0개", DrawKit.rows.empty?)

# ---------------------------------------------------------------- 4
title "4. 크기 0 입력 차단 + 롤백"
Sketchup.reset_model!
ops_before = nil
begin
  DrawKit.build("영치수") do
    box "정상", 0, 0, 0, 100, 100, 100
    box "높이0", 0, 0, 0, 100, 100, 0
  end
rescue ArgumentError
  ops_before = Sketchup.active_model.operations.map(&:first)
end
check("abort_operation 호출", ops_before.include?(:abort))
check("commit_operation 미호출", !ops_before.include?(:commit))

# ---------------------------------------------------------------- 5
title "5. 원기둥 (다각형 근사 허용오차 자동 적용)"
Sketchup.reset_model!
bad = DrawKit.build("원기둥") do
  cyl "PILE-1", 1000, 1000, 0, 300, 2000, segments: 24
end
check("세그먼트 24 에서도 오탐 없음", bad.empty?)
w = DrawKit.rows.first[:size][0]
check("폭 600mm 근사 (실측 #{w}mm)", (w - 600).abs <= 12.0)

# ---------------------------------------------------------------- 6
title "6. 임의 단면 압출 (L형)"
Sketchup.reset_model!
bad = DrawKit.build("L형") do
  shape "L-1", [[0, 0], [600, 0], [600, 200], [200, 200], [200, 600], [0, 600]], 0, 3000
end
check("L형 압출 검증 통과", bad.empty?)

# ---------------------------------------------------------------- 7
title "7. 검증 통과 시에만 저장"
Sketchup.reset_model!
DrawKit.build("저장", save_to: "C:/sketchup/ok.skp") { box "A", 0, 0, 0, 10, 10, 10 }
check("통과 시 저장됨", Sketchup.active_model.saved_path == "C:/sketchup/ok.skp")

# ---------------------------------------------------------------- 8
title "8. 치수가 실제와 다르면 검출 (검증 로직 자체 확인)"
Sketchup.reset_model!
DrawKit.build("검출", verify: false) { box "C4", 0, 0, 0, 400, 400, 2800 }
bad = DrawKit.verify([{ name: "C4", origin: [0, 0, 0], size: [400, 400, 3000] }])
check("높이 200mm 차이 검출", bad.size == 1)
bad = DrawKit.verify([{ name: "없는부재", origin: [0, 0, 0], size: [1, 1, 1] }])
check("미생성 부재 검출", bad.size == 1)

puts "\n" + "=" * 60
puts $fails.zero? ? "전체 통과" : "실패 #{$fails}건"
exit($fails.zero? ? 0 : 1)
