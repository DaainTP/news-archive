# drawkit.rb 드라이런 테스트 (SketchUp 없이 실행)
#   ruby tools/sketchup/test/test_drawkit.rb
require_relative "su_stub"
load File.expand_path("../drawkit.rb", __dir__)

def case_title(t)
  puts "\n=== #{t} ==="
end

fail_count = 0
def check(label, cond)
  puts((cond ? "  [OK]   " : "  [FAIL] ") + label)
  cond
end

# ---------------------------------------------------------------- 1. 기본 박스
case_title "1. 단위 환산 / 기본 박스 (500×500×3000mm 기둥)"
PARTS = [
  { name: "C1-기둥",   x: 0,    y: 0,    z: 0,    w: 500,  d: 500,  h: 3000 },
  { name: "C2-기둥",   x: 5000, y: 0,    z: 0,    w: 500,  d: 500,  h: 3000 },
  { name: "G1-큰보",   x: 500,  y: 0,    z: 2400, w: 4500, d: 400,  h: 600  },
  { name: "SLAB-1",    x: 0,    y: 0,    z: 3000, w: 5500, d: 3000, h: 150  }
]

DrawKit.build("테스트 모델") do |_m|
  PARTS.each { |p| DrawKit.box(**p) }
end

EXPECTED = PARTS.map { |p| { name: p[:name], origin: [p[:x], p[:y], p[:z]], size: [p[:w], p[:d], p[:h]] } }
bad = DrawKit.verify(EXPECTED)
fail_count += 1 unless check("치수표 4개 부재 전부 일치", bad.empty?)

# ---------------------------------------------------------------- 2. 중첩 그룹
case_title "2. assembly 하위 부재도 verify 대상에 들어오는가"
Sketchup.reset_model!
asm = nil
DrawKit.build("중첩 테스트") do |_m|
  asm = DrawKit.assembly("STR-1층")
  DrawKit.box(name: "C3-기둥", x: 0, y: 0, z: 0, w: 400, d: 400, h: 2800, parent: asm)
  DrawKit.box(name: "G2-작은보", x: 400, y: 0, z: 2300, w: 3000, d: 300, h: 500, parent: asm)
end
exp2 = [
  { name: "C3-기둥",   origin: [0, 0, 0],      size: [400, 400, 2800] },
  { name: "G2-작은보", origin: [400, 0, 2300], size: [3000, 300, 500] }
]
bad2 = DrawKit.verify(exp2)
fail_count += 1 unless check("중첩 부재 2개 탐색 및 일치", bad2.empty?)

# ---------------------------------------------------------------- 3. 불일치 탐지
case_title "3. 치수가 틀리면 잡아내는가 (의도적 오류)"
Sketchup.reset_model!
DrawKit.build("오류 테스트") { |_m| DrawKit.box(name: "C4", x: 0, y: 0, z: 0, w: 400, d: 400, h: 2800) }
bad3 = DrawKit.verify([{ name: "C4", origin: [0, 0, 0], size: [400, 400, 3000] }])
fail_count += 1 unless check("높이 200mm 차이를 검출", bad3.size == 1)

# ---------------------------------------------------------------- 4. 누락 탐지
case_title "4. 치수표에 있는데 생성 안 된 부재를 잡아내는가"
bad4 = DrawKit.verify([{ name: "존재하지않는부재", origin: [0, 0, 0], size: [100, 100, 100] }])
fail_count += 1 unless check("미생성 부재 검출", bad4.size == 1)

# ---------------------------------------------------------------- 5. 원기둥
case_title "5. cylinder 바운딩박스 (반지름 300 -> 지름 600mm)"
Sketchup.reset_model!
DrawKit.build("원기둥 테스트") { |_m| DrawKit.cylinder(name: "PILE-1", x: 1000, y: 1000, z: 0, r: 300, h: 2000, segments: 96) }
rows = DrawKit.audit
w = rows.first[:size][0]
fail_count += 1 unless check("폭 600mm 근사 (실측 #{w}mm)", (w - 600).abs <= 2.0)
fail_count += 1 unless check("높이 2000mm", (rows.first[:size][2] - 2000).abs <= 0.5)

# ---------------------------------------------------------------- 6. 예외 롤백
case_title "6. 오류 발생 시 abort_operation 으로 롤백되는가"
Sketchup.reset_model!
begin
  DrawKit.build("롤백 테스트") do |_m|
    DrawKit.box(name: "정상", x: 0, y: 0, z: 0, w: 100, d: 100, h: 100)
    DrawKit.box(name: "높이0", x: 0, y: 0, z: 0, w: 100, d: 100, h: 0)   # 의도적 오류
  end
rescue ArgumentError => e
  puts "  예외 메시지: #{e.message}"
end
ops = Sketchup.active_model.operations.map(&:first)
fail_count += 1 unless check("abort_operation 호출됨", ops.include?(:abort))
fail_count += 1 unless check("commit_operation 미호출", !ops.include?(:commit))

# ---------------------------------------------------------------- 7. 이름 중복
case_title "7. 그룹 이름이 중복되면 경고하는가"
Sketchup.reset_model!
DrawKit.build("중복 테스트") do |_m|
  DrawKit.box(name: "C1", x: 0,    y: 0, z: 0, w: 400, d: 400, h: 2800)
  DrawKit.box(name: "C1", x: 5000, y: 0, z: 0, w: 400, d: 400, h: 2800)
end
dup = DrawKit.verify([{ name: "C1", origin: [0, 0, 0], size: [400, 400, 2800] }])
fail_count += 1 unless check("중복 이름 경고 발생", dup.any? { |b| b[:reason].to_s.include?("중복") })

# ---------------------------------------------------------------- 8. 저장
case_title "8. save_as"
Sketchup.reset_model!
DrawKit.build("저장 테스트") { |_m| DrawKit.box(name: "A", x: 0, y: 0, z: 0, w: 10, d: 10, h: 10) }
DrawKit.save_as("C:/sketchup/test.skp")
fail_count += 1 unless check("경로 기록됨", Sketchup.active_model.saved_path == "C:/sketchup/test.skp")

puts "\n" + "=" * 60
puts fail_count.zero? ? "전체 통과" : "실패 #{fail_count}건"
exit(fail_count.zero? ? 0 : 1)
