# =============================================================================
# DrawKit 자동 설치
#
# 사용법: SketchUp 실행 → 상단 메뉴 [창(Window)] → [Ruby 콘솔(Ruby Console)]
#         → 이 파일 내용 전체를 복사해 콘솔 입력칸에 붙여넣고 Enter
#
# 폴더를 직접 찾을 필요 없다. 설치 위치는 이 스크립트가 알아서 찾는다.
# 설치 후에는 SketchUp 을 껐다 켜도 DrawKit 이 계속 살아 있다.
# =============================================================================

DRAWKIT_SOURCE = <<'DRAWKIT_SRC'
# DrawKit - SketchUp mm 단위 모델링 헬퍼
#
# 최초 1회만 설치하면 이후 모델링 스크립트는 치수만 담으면 된다.
#   설치: 이 파일을 SketchUp Plugins 폴더에 복사 (README 참조) → SketchUp 재시작
#   확인: Ruby 콘솔에 defined?(DrawKit)  →  "constant" 가 나오면 설치 완료
#
# 사용 예 (이게 전부다):
#   DrawKit.build("1층 골조") do
#     box "C1-1", 0,    0, 0,    500, 500, 3000
#     box "C1-2", 5000, 0, 0,    500, 500, 3000
#     box "G1-1", 500,  0, 2400, 4500, 400, 600
#   end
#
# 규칙: 모든 숫자는 mm. 순서는 항상  이름, 원점X,Y,Z, 크기W,D,H.

module DrawKit
  VERSION = "2.0".freeze

  # ---------- 단위 ----------

  # mm 숫자 -> SketchUp 내부 길이
  def self.mm(v)
    v.to_f.mm
  end

  # SketchUp 내부 길이 -> mm 숫자
  def self.to_mm(len)
    (len.to_f * 25.4).round(1)
  end

  def self.pt(x, y, z)
    Geom::Point3d.new(mm(x), mm(y), mm(z))
  end

  def self.use_mm!(model = Sketchup.active_model)
    o = model.options["UnitsOptions"]
    o["LengthFormat"] = Length::Decimal
    o["LengthUnit"] = Length::Millimeter
    o["LengthPrecision"] = 1
    true
  rescue StandardError
    false
  end

  # ---------- 생성 DSL ----------
  #
  # build 블록 안에서는 box / cyl / shape / group 만 쓰면 된다.
  # 입력한 치수는 자동으로 기록되어 블록 종료 직후 스스로 검증된다.

  class Builder
    attr_reader :expected

    def initialize(model)
      @model = model
      @stack = [model.active_entities]
      @expected = []
      @names = {}
    end

    # 직육면체: 이름, 원점X,Y,Z, 크기W,D,H (mm)
    def box(name, x, y, z, w, d, h, color: nil, layer: nil)
      raise ArgumentError, "#{name}: 크기에 0 이 있다 (W=#{w} D=#{d} H=#{h})" if w.to_f.zero? || d.to_f.zero? || h.to_f.zero?

      g = new_group(name, color, layer)
      f = g.entities.add_face(
        DrawKit.pt(x,     y,     z),
        DrawKit.pt(x + w, y,     z),
        DrawKit.pt(x + w, y + d, z),
        DrawKit.pt(x,     y + d, z)
      )
      f.reverse! if f.normal.z < 0
      f.pushpull(DrawKit.mm(h))

      record(name, [x, y, z], [w.abs, d.abs, h.abs])
      g
    end

    # 수직 원기둥: 이름, 중심X,Y, 바닥Z, 반지름R, 높이H (mm)
    def cyl(name, x, y, z, r, h, segments: 24, color: nil, layer: nil)
      raise ArgumentError, "#{name}: 반지름/높이에 0 이 있다 (R=#{r} H=#{h})" if r.to_f.zero? || h.to_f.zero?

      g = new_group(name, color, layer)
      circle = g.entities.add_circle(DrawKit.pt(x, y, z), Geom::Vector3d.new(0, 0, 1), DrawKit.mm(r), segments)
      f = g.entities.add_face(circle)
      f.reverse! if f.normal.z < 0
      f.pushpull(DrawKit.mm(h))

      # 다각형 근사라 폭은 지름보다 약간 작다. 검증 허용오차를 별도로 둔다.
      record(name, [x - r, y - r, z], [2 * r, 2 * r, h.abs], tol: 2.0 + r.abs * 0.02)
      g
    end

    # 임의 폐다각형 압출: 이름, [[x1,y1],[x2,y2],...], 바닥Z, 높이H (mm)
    def shape(name, profile, z, h, color: nil, layer: nil)
      raise ArgumentError, "#{name}: profile 은 3점 이상 필요" if profile.size < 3

      g = new_group(name, color, layer)
      f = g.entities.add_face(profile.map { |px, py| DrawKit.pt(px, py, z) })
      f.reverse! if f.normal.z < 0
      f.pushpull(DrawKit.mm(h))

      xs = profile.map { |px, _| px }
      ys = profile.map { |_, py| py }
      record(name, [xs.min, ys.min, z], [xs.max - xs.min, ys.max - ys.min, h.abs])
      g
    end

    # 하위 부재를 묶는 상위 그룹. 블록 안에서 box/cyl/shape 를 그대로 쓴다.
    def group(name, color: nil, layer: nil)
      g = new_group(name, color, layer)
      @stack.push(g.entities)
      begin
        yield if block_given?
      ensure
        @stack.pop
      end
      g
    end

    private

    def new_group(name, color, layer)
      g = @stack.last.add_group
      g.name = name.to_s
      g.material = color if color
      g.layer = layer if layer
      g
    end

    def record(name, origin, size, tol: nil)
      key = name.to_s
      raise ArgumentError, "부재명 중복: #{key} — 이름이 검증 키이므로 고유해야 한다 (C1-1, C1-2 …)" if @names[key]

      @names[key] = true
      @expected << { name: key, origin: origin.map(&:to_f), size: size.map(&:to_f), tol: tol }
    end
  end

  # 생성 + 검증 + (선택) 저장을 한 번에.
  #   verify: false  → 검증 생략
  #   save_to: 경로  → 검증 통과 시에만 .skp 저장
  def self.build(op_name, model: Sketchup.active_model, verify: true, save_to: nil, &blk)
    use_mm!(model)
    builder = Builder.new(model)

    model.start_operation(op_name, true)
    begin
      builder.instance_eval(&blk)
      model.commit_operation
    rescue StandardError => e
      model.abort_operation
      puts "생성 실패 — 모델은 실행 전 상태로 되돌렸다: #{e.message}"
      raise
    end

    bad = verify ? self.verify(builder.expected, model: model) : []
    save_as(save_to, model: model) if save_to && bad.empty?
    bad
  end

  # ---------- 검증 ----------

  # 모델 안의 모든 그룹을 재귀 수집한다(중첩 포함). 반환: [[group, depth], ...]
  def self.collect_groups(ents, depth = 0, acc = [])
    ents.grep(Sketchup::Group).each do |g|
      acc << [g, depth]
      collect_groups(g.entities, depth + 1, acc)
    end
    acc
  end

  def self.rows(model = Sketchup.active_model)
    collect_groups(model.entities).map do |g, depth|
      bb = g.bounds
      { name: g.name.to_s, depth: depth,
        origin: [to_mm(bb.min.x), to_mm(bb.min.y), to_mm(bb.min.z)],
        size:   [to_mm(bb.width), to_mm(bb.height), to_mm(bb.depth)] }
    end
  end

  # 실제 바운딩박스를 mm 표로 출력한다(수동 확인용).
  def self.audit(model = Sketchup.active_model)
    list = rows(model)
    puts "%-30s %-24s %s" % ["부재명", "원점 X,Y,Z (mm)", "크기 W×D×H (mm)"]
    puts "-" * 84
    list.each do |r|
      puts "%-30s %-24s %s" % [("  " * r[:depth]) + r[:name], r[:origin].join(", "), r[:size].join(" × ")]
    end
    puts "-" * 84
    puts "부재 수: #{list.size}"
    list
  end

  # 입력 치수와 실제 모델을 대조. 통과하면 한 줄, 실패하면 불일치 부재만 출력한다.
  def self.verify(expected, tol: 0.5, model: Sketchup.active_model)
    actual = rows(model)
    counts = actual.each_with_object(Hash.new(0)) { |r, h| h[r[:name]] += 1 }
    index = actual.each_with_object({}) { |r, h| h[r[:name]] ||= r }

    bad = []
    expected.each do |e|
      name = e[:name]
      t = e[:tol] || tol

      if counts[name].to_i > 1
        bad << { name: name, reason: "이름이 #{counts[name]}개 중복되어 대조 불가" }
        next
      end

      a = index[name]
      if a.nil?
        bad << { name: name, reason: "생성되지 않음" }
        next
      end

      diff = []
      3.times do |i|
        diff << "원점#{%w[X Y Z][i]} 입력 #{e[:origin][i]} / 실제 #{a[:origin][i]}" if (e[:origin][i] - a[:origin][i]).abs > t
        diff << "크기#{%w[W D H][i]} 입력 #{e[:size][i]} / 실제 #{a[:size][i]}"     if (e[:size][i]   - a[:size][i]).abs   > t
      end
      bad << { name: name, reason: diff.join(" | ") } unless diff.empty?
    end

    if bad.empty?
      puts "검증 통과 — 부재 #{expected.size}개가 입력 치수와 일치"
    else
      puts "검증 실패 #{bad.size}건 (나머지 #{expected.size - bad.size}개는 정상):"
      bad.each { |b| puts "  - #{b[:name]}: #{b[:reason]}" }
    end
    bad
  end

  # ---------- 저장 ----------

  def self.save_as(path, model: Sketchup.active_model)
    return false if path.nil? || path.to_s.empty?

    ok = model.save(path)
    puts(ok ? "저장 완료: #{path}" : "저장 실패: #{path}")
    ok
  end
end

puts "DrawKit #{DrawKit::VERSION} 준비됨"
DRAWKIT_SRC

require 'fileutils'

# File.writable? 는 Windows 의 ACL 을 제대로 반영하지 못한다(Program Files 등).
# 실제로 임시 파일을 써 보고 판단한다.
def drawkit_writable?(dir)
  return false unless File.directory?(dir)

  probe = File.join(dir, ".drawkit_write_test_#{Time.now.to_i}")
  begin
    File.open(probe, "w") { |f| f.write("1") }
    true
  rescue StandardError
    false
  ensure
    begin
      File.delete(probe) if File.exist?(probe)
    rescue StandardError
      nil
    end
  end
end

# SketchUp 버전별 사용자 플러그인 폴더를 찾는다. 쓰기 가능한 곳을 우선한다.
def drawkit_candidate_dirs
  dirs = []

  # 1) SketchUp 이 이미 읽고 있는 Plugins 경로 (가장 확실)
  $LOAD_PATH.each { |p| dirs << p.to_s if p.to_s =~ /Plugins[\/\\]?$/i }

  # 2) SketchUp API 가 알려주는 경로
  begin
    f = Sketchup.find_support_file("Plugins")
    dirs << f.to_s if f
  rescue StandardError
    nil
  end

  # 3) 플랫폼별 표준 사용자 폴더 (SketchUp 2017 이후 규칙)
  year = Sketchup.version.to_i + 2000
  if ENV['APPDATA']
    dirs << File.join(ENV['APPDATA'].to_s.tr("\\", "/"), 'SketchUp', "SketchUp #{year}", 'SketchUp', 'Plugins')
  end
  if ENV['HOME']
    dirs << File.join(ENV['HOME'].to_s, 'Library', 'Application Support', "SketchUp #{year}", 'SketchUp', 'Plugins')
  end

  dirs.map { |d| d.tr("\\", "/").sub(/\/+$/, "") }.uniq
end

def drawkit_install!
  candidates = drawkit_candidate_dirs
  target = candidates.find { |d| drawkit_writable?(d) }

  if target.nil?
    # 폴더가 아직 없으면 표준 위치에 만든다.
    fallback = candidates.find { |d| d =~ /APPDATA|AppData|Application Support/i } || candidates.last
    begin
      FileUtils.mkdir_p(fallback)
      target = fallback if drawkit_writable?(fallback)
    rescue StandardError => e
      puts "폴더 생성 실패 (#{fallback}): #{e.message}"
    end
  end

  if target.nil?
    puts "설치 실패: 쓰기 가능한 Plugins 폴더를 찾지 못했다."
    puts "찾아본 경로:"
    candidates.each { |d| puts "  - #{d}" }
    puts "이 목록을 그대로 알려주면 다른 방법을 안내한다."
    return false
  end

  path = File.join(target, "drawkit.rb")
  begin
    File.open(path, "w:UTF-8") { |f| f.write(DRAWKIT_SOURCE) }
  rescue StandardError => e
    puts "파일 쓰기 실패 (#{path}): #{e.message}"
    return false
  end

  load path

  puts ""
  puts "설치 완료"
  puts "  위치: #{path}"
  puts "  버전: DrawKit #{DrawKit::VERSION}"
  puts "  지금 바로 사용할 수 있고, SketchUp 을 재시작해도 유지된다."
  puts ""
  true
end

drawkit_install!
