# DrawKit - SketchUp mm 단위 모델링 헬퍼
#
# 사용법 (SketchUp Ruby 콘솔 또는 생성된 build 스크립트 상단에서):
#   load "C:/path/to/drawkit.rb"
#
# 규칙
#   - 모든 인자는 mm(밀리미터) 단위 숫자. 내부에서 .mm 으로 변환한다.
#   - SketchUp 은 생 숫자를 인치로 해석하므로 직접 좌표를 쓰지 말고 이 모듈을 쓴다.

module DrawKit
  VERSION = "1.0".freeze

  # ---------- 단위 ----------

  # mm 숫자 -> SketchUp 내부 길이(Length)
  def self.mm(v)
    v.to_f.mm
  end

  # SketchUp 내부 길이 -> mm 숫자(소수 1자리 반올림)
  def self.to_mm(len)
    (len.to_f * 25.4).round(1)
  end

  def self.pt(x, y, z)
    Geom::Point3d.new(mm(x), mm(y), mm(z))
  end

  # 모델 단위를 mm 로 강제 (십진 밀리미터)
  def self.use_mm!(model = Sketchup.active_model)
    o = model.options["UnitsOptions"]
    o["LengthFormat"] = Length::Decimal
    o["LengthUnit"]   = Length::Millimeter
    o["LengthPrecision"] = 1
    true
  rescue StandardError
    false
  end

  # ---------- 트랜잭션 ----------

  # 한 번의 실행취소(Undo) 단위로 묶어서 생성한다. 예외 발생 시 전체 롤백.
  def self.build(op_name, model = Sketchup.active_model)
    use_mm!(model)
    model.start_operation(op_name, true)
    begin
      result = yield(model)
      model.commit_operation
      result
    rescue StandardError => e
      model.abort_operation
      raise e
    end
  end

  # ---------- 형상 ----------

  # 직육면체. (x, y, z) = 최소 코너 원점, w/d/h = X/Y/Z 크기 (mm)
  def self.box(name:, x:, y:, z:, w:, d:, h:, parent: nil, color: nil, layer: nil)
    raise ArgumentError, "#{name}: w/d/h 는 0 이 될 수 없다 (w=#{w}, d=#{d}, h=#{h})" if w.to_f.zero? || d.to_f.zero? || h.to_f.zero?

    ents = parent ? group_entities(parent) : Sketchup.active_model.active_entities
    g = ents.add_group
    g.name = name

    face = g.entities.add_face(
      pt(x,     y,     z),
      pt(x + w, y,     z),
      pt(x + w, y + d, z),
      pt(x,     y + d, z)
    )
    face.reverse! if face.normal.z < 0
    face.pushpull(mm(h))

    g.material = color if color
    g.layer = layer if layer
    g
  end

  # 임의 폐다각형 프로파일을 Z 방향으로 압출.
  # profile: [[x1,y1], [x2,y2], ...] (mm, XY평면), z: 바닥 높이, h: 압출 높이
  def self.extrude(name:, profile:, z:, h:, parent: nil, color: nil, layer: nil)
    raise ArgumentError, "#{name}: profile 은 3점 이상 필요" if profile.size < 3

    ents = parent ? group_entities(parent) : Sketchup.active_model.active_entities
    g = ents.add_group
    g.name = name

    face = g.entities.add_face(profile.map { |px, py| pt(px, py, z) })
    face.reverse! if face.normal.z < 0
    face.pushpull(mm(h))

    g.material = color if color
    g.layer = layer if layer
    g
  end

  # 수직 원기둥. (x, y) = 중심, r = 반지름, h = 높이 (mm)
  def self.cylinder(name:, x:, y:, z:, r:, h:, segments: 24, parent: nil, color: nil, layer: nil)
    ents = parent ? group_entities(parent) : Sketchup.active_model.active_entities
    g = ents.add_group
    g.name = name

    circle = g.entities.add_circle(pt(x, y, z), Geom::Vector3d.new(0, 0, 1), mm(r), segments)
    face = g.entities.add_face(circle)
    face.reverse! if face.normal.z < 0
    face.pushpull(mm(h))

    g.material = color if color
    g.layer = layer if layer
    g
  end

  # 여러 부재를 묶는 상위 그룹
  def self.assembly(name, parent = nil)
    ents = parent ? group_entities(parent) : Sketchup.active_model.active_entities
    g = ents.add_group
    g.name = name
    g
  end

  # ---------- 검증 ----------

  # 모델 안의 모든 그룹을 재귀적으로 수집한다. assembly 하위 부재도 빠짐없이 잡기 위함.
  # 반환: [[group, depth], ...]
  def self.collect_groups(ents, depth = 0, acc = [])
    ents.grep(Sketchup::Group).each do |g|
      acc << [g, depth]
      collect_groups(g.entities, depth + 1, acc)
    end
    acc
  end

  # 생성된 그룹의 실제 바운딩박스를 mm 로 뽑아 치수표와 대조할 수 있게 출력한다.
  # groups 를 생략하면 모델 전체(중첩 포함)를 대상으로 한다.
  def self.audit(groups = nil, model: Sketchup.active_model)
    pairs = if groups
              Array(groups).flatten.compact.map { |g| [g, 0] }
            else
              collect_groups(model.entities)
            end

    rows = pairs.map do |g, depth|
      bb = g.bounds
      {
        name: g.name.to_s,
        depth: depth,
        origin: [to_mm(bb.min.x), to_mm(bb.min.y), to_mm(bb.min.z)],
        size:   [to_mm(bb.width), to_mm(bb.height), to_mm(bb.depth)]
      }
    end

    puts "%-30s %-24s %s" % ["부재명", "원점 X,Y,Z (mm)", "크기 W×D×H (mm)"]
    puts "-" * 84
    rows.each do |r|
      puts "%-30s %-24s %s" % [
        ("  " * r[:depth]) + r[:name],
        r[:origin].join(", "),
        r[:size].join(" × ")
      ]
    end
    puts "-" * 84
    puts "부재 수: #{rows.size}"

    dups = rows.map { |r| r[:name] }.tally.select { |_, c| c > 1 }
    unless dups.empty?
      puts "경고: 그룹 이름 중복 → " + dups.map { |n, c| "#{n}(#{c}개)" }.join(", ")
      puts "      이름이 검증 키이므로 C1-1, C1-2 처럼 고유하게 부여할 것."
    end

    rows
  end

  # 치수표(expected)와 실제 audit 결과를 비교. 불일치 부재만 반환한다.
  # expected: [{name:, origin:[x,y,z], size:[w,d,h]}, ...]
  def self.verify(expected, tol: 0.5, model: Sketchup.active_model)
    actual = audit(nil, model: model)
    counts = actual.map { |r| r[:name] }.tally
    index = actual.each_with_object({}) { |r, h| h[r[:name]] ||= r }

    bad = []
    expected.each do |e|
      name = e[:name]

      if counts[name].to_i > 1
        bad << { name: name, reason: "이름이 #{counts[name]}개 중복되어 대조 불가 — 고유한 이름으로 재생성할 것" }
        next
      end

      a = index[name]
      if a.nil?
        bad << { name: name, reason: "생성되지 않음" }
        next
      end

      diff = []
      3.times do |i|
        diff << "원점#{%w[X Y Z][i]} 기대 #{e[:origin][i]} / 실제 #{a[:origin][i]}" if (e[:origin][i] - a[:origin][i]).abs > tol
        diff << "크기#{%w[W D H][i]} 기대 #{e[:size][i]} / 실제 #{a[:size][i]}"     if (e[:size][i]   - a[:size][i]).abs   > tol
      end
      bad << { name: name, reason: diff.join(" | ") } unless diff.empty?
    end

    if bad.empty?
      puts "검증 통과: 치수표 #{expected.size}개 부재가 모두 일치 (허용오차 #{tol}mm)"
    else
      puts "검증 실패 #{bad.size}건:"
      bad.each { |b| puts "  - #{b[:name]}: #{b[:reason]}" }
    end
    bad
  end

  # ---------- 저장 ----------

  # .skp 로 저장. path 는 절대경로.
  def self.save_as(path, model: Sketchup.active_model)
    ok = model.save(path)
    puts(ok ? "저장 완료: #{path}" : "저장 실패: #{path}")
    ok
  end

  def self.group_entities(parent)
    parent.is_a?(Sketchup::Group) ? parent.entities : parent
  end
  private_class_method :group_entities
end

puts "DrawKit #{DrawKit::VERSION} 로드 완료"
