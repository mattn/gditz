#!/usr/bin/env ruby
require 'gtk2'
require 'pathname'
require 'trollop'; include Trollop
require 'ditz'

CONFIG_FN = ".ditz-config"
PLUGIN_FN = ".ditz-plugins"
GDITZ_VERSION = "0.1"

config_dir = Ditz::find_dir_containing CONFIG_FN
plugin_dir = Ditz::find_dir_containing PLUGIN_FN

$opts = options do
  version "gditz #{GDITZ_VERSION}"
  opt :issue_dir, "Issue database dir", :default => ".ditz"
  opt :config_file, "Configuration file", :default => File.join(config_dir || ".", CONFIG_FN)
  opt :plugins_file, "Plugins file", :default => File.join(plugin_dir || ".", PLUGIN_FN)
  opt :verbose, "Verbose output", :default => false
  opt :list_hooks, "List all hooks and descriptions, and quit.", :short => 'l', :default => false
  stop_on_unknown
end

begin
  Ditz::load_plugins($opts[:plugin_file])
rescue SystemCallError => e
  Ditz::debug "can't load plugins file: #{e.message}"
end

config = begin
  Ditz::Config.from($opts[:config_file])
rescue SystemCallError => e
  Ditz::Config.new()
end

config.issue_dir = $opts[:issue_dir] if $opts[:issue_dir] != config.issue_dir
issue_dir = Pathname.new(config.issue_dir)
project_root = Ditz::find_dir_containing(issue_dir + Ditz::FileStorage::PROJECT_FN)
die "No #{issue_dir} directory---use 'ditz init' to initialize" unless project_root
project_root += issue_dir

class StockButton < Gtk::Button
  def initialize(text = nil, stock = nil, textalign = :horiz)
    super()
    align = Gtk::Alignment.new(0.5, 0.5, 0, 0)
    add align
    textalign == :horiz ? box = Gtk::HBox.new(false, 0) : box = Gtk::VBox.new(false, 0)
    align.add box
    @widget_image = Gtk::Image.new(stock, Gtk::IconSize::BUTTON)
    box.pack_start(@widget_image, false, false, 2)
    @widget_label = Gtk::Label.new(text)
    @widget_label.use_underline = true
    @widget_label.show
    box.pack_start(@widget_label, false, false, 2)
  end
private
  @widget_image
  @widget_label
end

## IssueChooseDialog : choose disposition type
class IssueChooseDialog < Gtk::Dialog
  def initialize(parent, issue)
    super("gDitz - #{issue.name}", parent, Gtk::Dialog::MODAL,
        ['_OK', 1],
        ['_Cancel', 2]
    )
    @issue_disp = Gtk::ComboBox::new()
    Ditz::Issue::DISPOSITION_STRINGS.each {|a| @issue_disp.append_text(a[1].to_s)}
    @issue_disp.set_active(0)
    self.vbox.pack_start(@issue_disp, true, true, 0)
  end

  def issue_disp; Ditz::Issue::DISPOSITION_STRINGS.index(@issue_disp.active_text) end
end

## IssueDescDialog : edit issue description
class IssueDescDialog < Gtk::Dialog
  def initialize(parent, ctx, issue)
    @parent = parent
    @ctx = ctx
    name = issue ? issue.name : ''
    super("gDitz - #{name}", @parent, Gtk::Dialog::MODAL)

    @issue_comp = Gtk::ComboBox::new()
    @ctx[:project].components.each {|a| @issue_comp.append_text(a.name)}
    self.vbox.pack_start(@issue_comp, true, true, 0)

    @issue_type = Gtk::ComboBox::new()
    ['bugfix', 'feature', 'task'].each {|a| @issue_type.append_text(a)}
    self.vbox.pack_start(@issue_type, true, true, 0)

    @issue_title = Gtk::Entry::new()
    self.vbox.add(@issue_title)

    textview = Gtk::TextView::new()
    @issue_desc = textview.buffer()
    textview.set_editable(true)
    scroll = Gtk::ScrolledWindow::new()
    scroll.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    scroll.set_shadow_type(Gtk::SHADOW_IN)
    scroll.add(textview)
    self.vbox.pack_end(scroll, false, false, 0)
    self.default_response = 2

    if issue
      self.add_action_widget(StockButton::new('_Update Issue', Gtk::Stock::SAVE), 1)
      self.add_action_widget(StockButton::new('Clo_se Issue', Gtk::Stock::CLOSE), 2)
      self.add_action_widget(StockButton::new('_Cancel', Gtk::Stock::CANCEL), 3)
      @issue_comp.set_active(@ctx[:project].components.map{|x| x.name}.index(issue.component))
      @issue_type.set_active(Ditz::Issue::TYPE_ORDER[issue.type])
      @issue_title.set_text(issue.title)
      @issue_desc.set_text(issue.desc)
    else
      self.add_action_widget(StockButton::new('_Update Issue', Gtk::Stock::SAVE), 1)
      self.add_action_widget(StockButton::new('_Cancel', Gtk::Stock::CANCEL), 3)
      @issue_comp.set_active(0)
      @issue_type.set_active(0)
    end
  end

  def issue_comp; @issue_comp.active end
  def issue_type; Ditz::Issue::TYPE_ORDER.index(@issue_type.active) end
  def issue_title; @issue_title.text end
  def issue_desc; @issue_desc.get_text() end

private
  @ctx
  @parent
end

## IssueListView : list view control for issues
class IssueListView < Gtk::TreeView
  COLUMNS = [
      {:name => 'id',    :width => 100},
      {:name => 'title', :width =>  -1}
  ]
  def initialize(parent, ctx)
    @parent = parent
    @ctx = ctx
    @model = Gtk::ListStore.new(String, String)
    super @model
    crtest = Gtk::CellRendererText.new()
    COLUMNS.each_with_index do |col, idx|
      tvc = Gtk::TreeViewColumn.new(col[:name], crtest, :text => idx)
      tvc.min_width = col[:width].to_i if col[:width].to_i > 0
      tvc.resizable = true
      self.append_column(tvc)
    end
    self.signal_connect "row-activated" do
      path = self.selection.selected_rows()[0]
      iter = @model.get_iter(path)
      issue = (@ctx[:project].issues.select { |i| i.name == iter[0] }).first
      self.edit_issue(issue)
    end
  end

  def edit_issue(issue)
    descdialog = IssueDescDialog.new(@parent, @ctx, issue)
    descdialog.window_position = Gtk::Window::POS_CENTER_ON_PARENT
    descdialog.show_all()
    descdialog.run() do |response|
      case response
        when 1
          issue.type = descdialog.issue_type
          issue.title = descdialog.issue_title
          issue.desc = descdialog.issue_desc
          issue.changed!
          @ctx[:storage].save(@ctx[:project])
          self.update_issues()
        when 2
          choosedialog = IssueChooseDialog.new(descdialog, issue)
          choosedialog.window_position = Gtk::Window::POS_CENTER_ON_PARENT
          choosedialog.show_all()
          who = "#{@ctx[:config].name} <#{@ctx[:config].email}"
          if choosedialog.run() == 1
            issue.close(choosedialog.issue_disp, who, '') if choosedialog.run() == 1
            issue.changed!
          end
          choosedialog.destroy()
          @ctx[:storage].save(@ctx[:project])
          self.update_issues()
      end
    end
    descdialog.destroy()
  end

  def update_issues()
    @model.clear()
    releases ||= @ctx[:project].unreleased_releases + [:unassigned]
    releases = [*releases]
    releases.each do |r|
      issues = @ctx[:project].issues_for_release r
      issues = issues.select { |i| i.open? } unless @ctx[:option][:all]

      issues.each do |issue|
        iter = @model.append()
        iter[0] = issue.name
        iter[1] = issue.title
      end
    end
  end

private
  @ctx
  @model
  @parent
end

## IssueListWindow : main window
class IssueListWindow < Gtk::Window
  def initialize(ctx)
    @ctx = ctx
    super()
    self.set_title('gDitz')
    self.set_default_size(400, 300)
    self.signal_connect "destroy" do
      self.save_if_changed()
      Gtk.main_quit()
    end

    vbox = Gtk::VBox.new(false, 6)
    swin = Gtk::ScrolledWindow.new()
    swin.set_policy Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC
    @ilist = IssueListView.new(self, @ctx)
    @ilist.update_issues()
    swin.add(@ilist)
    vbox.pack_start(swin, true, true, 0)

    hbox = Gtk::HBox.new(false, 6)

    add_issue = StockButton.new('_Add Issue', Gtk::Stock::EDIT)
    add_issue.signal_connect('clicked') do |add_issue| self.create_issue() end
    hbox.add(add_issue)

    refresh = StockButton::new('_Refresh', Gtk::Stock::REFRESH)
    refresh.signal_connect('clicked') do |refresh| @ilist.update_issues() end
    hbox.add(refresh)

    quit = StockButton::new('_Quit', Gtk::Stock::QUIT)
    quit.signal_connect('clicked') do |quit| self.destroy() end
    hbox.add(quit)

    vbox.pack_start(hbox, false, false, 0)
    self.add(vbox)
  end

  def create_issue()
    descdialog = IssueDescDialog.new(self, @ctx, nil)
    descdialog.window_position = Gtk::Window::POS_CENTER_ON_PARENT
    descdialog.show_all()
    descdialog.run() do |response|
      case response
        when 1
          issue = Ditz::Issue::create([@ctx[:config], @ctx[:project]],
            :title => descdialog.issue_title,
            :desc => descdialog.issue_desc,
            :type => descdialog.issue_type,
            :component => @ctx[:project].components.name,
            :reporter => "#{@ctx[:config].name} <#{@ctx[:config].email}",
            :status => :unstarted,
            :create_time => Time.now
          )
          issue.project = @ctx[:project]
          @ctx[:project].add_issue(issue)
          @ctx[:storage].save(@ctx[:project])
      end
    end
    descdialog.destroy()
    @ilist.update_issues()
  end

  def save_if_changed()
    changed_issues = @ctx[:project].issues.select { |i| i.changed? }
    unless changed_issues.empty?
      @ctx[:storage].save @ctx[:project]
    end
  end

private
  @ctx
  @ilist
end

storage = Ditz::FileStorage.new(project_root)
project = begin
  storage.load()
rescue SystemCallError, Ditz::Project::Error => e
  die "#{e.message} (use 'init' to initialize)"
end

win = IssueListWindow.new({
  :config  => config,
  :project => project,
  :storage => storage,
  :option  => $opts
})
win.show_all()
Gtk.main()
