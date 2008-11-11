require 'gtk2'
require 'pathname'
require 'trollop'; include Trollop
require 'ditz'

CONFIG_FN = ".ditz-config"
PLUGIN_FN = ".ditz-plugins"

config_dir = Ditz::find_dir_containing CONFIG_FN
plugin_dir = Ditz::find_dir_containing PLUGIN_FN

$opts = options do
  version "ditz #{Ditz::VERSION}"
  opt :issue_dir, "Issue database dir", :default => "bugs"
  opt :config_file, "Configuration file", :default => File.join(config_dir || ".", CONFIG_FN)
  opt :plugins_file, "Plugins file", :default => File.join(plugin_dir || ".", PLUGIN_FN)
  opt :verbose, "Verbose output", :default => false
  opt :list_hooks, "List all hooks and descriptions, and quit.", :short => 'l', :default => false
  stop_on_unknown
end

$verbose = true if $opts[:verbose]
$config = begin
  Ditz::Config.from $opts[:config_file]
rescue SystemCallError => e
  Ditz::Config.new()
end
begin
  Ditz::load_plugins(".ditz-plugins")
rescue SystemCallError => e
  Ditz::debug "can't load plugins file: #{e.message}"
end

issue_dir = Pathname.new($config.issue_dir || '.ditz')
project_root = Ditz::find_dir_containing(issue_dir + Ditz::FileStorage::PROJECT_FN)
project_root += issue_dir
$storage = Ditz::FileStorage.new(project_root)
$project = begin
  $storage.load()
rescue SystemCallError, Ditz::Project::Error => e
  die "#{e.message} (use 'init' to initialize)"
end

#button = Gtk::Button::new()
#button.set_label('add issue')
#button.signal_connect('clicked') do |button|
#  DitzUtil.add_ditz_issue(
#      :title => $title.text(),
#      :desc => $desc.text(),
#      :type => $type.active_text(),
#      :component => "gui",
#      :reporter => "hehehe <your@example.com>",
#       :status => :unstarted,
#       :create_time => Time.now
#  )
#end
#vb.pack_start(button, false, false, 0)

class IssueDialog < Gtk::Dialog
  def initialize(parent, issue)
    super("gDitz - #{issue.name}", parent, Gtk::Dialog::MODAL,
        [Gtk::Stock::OK,     Gtk::Dialog::RESPONSE_OK],
        [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL]
    )

    @issue_type = Gtk::ComboBox::new()
    ['bugfix', 'feature', 'task'].each {|a| @issue_type.append_text(a)}
    begin
      @issue_type.set_active(Ditz::Issue::TYPE_ORDER.map {|a| a[0].to_s}.index(issue.type))
    rescue
      @issue_type.set_active(0)
    end
    self.vbox.pack_start(@issue_type, true, true, 0)

    @issue_title = Gtk::Entry::new()
    @issue_title.set_text(issue.title)
    self.vbox.add(@issue_title)

    textview = Gtk::TextView::new()
    @issue_desc = textview.buffer()
    @issue_desc.set_text(issue.desc)
    textview.set_editable(true)
    scroll = Gtk::ScrolledWindow::new()
    scroll.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    scroll.set_shadow_type(Gtk::SHADOW_IN)
    scroll.add(textview)
    self.vbox.pack_end(scroll, false, false, 0)
    self.default_response = Gtk::Dialog::ResponseType::OK
  end

  def issue_type; @issue_type end
  def issue_title; @issue_title end
  def issue_desc; @issue_desc end
end

class IssueListView < Gtk::TreeView
  COLUMNS = ["id", "title"]
  def initialize(parent)
    @model = Gtk::ListStore.new(String, String)
    super @model
    crtest = Gtk::CellRendererText.new()
    COLUMNS.each_with_index do |name, idx|
      col = Gtk::TreeViewColumn.new(name, crtest, :text => idx)
      col.resizable = true
      self.append_column(col)
    end
    self.signal_connect "row-activated" do
      path = self.selection.selected_rows()[0]
      iter = @model.get_iter(path)
      issue = ($project.issues.select { |i| i.name == iter[0] }).first
      dialog = IssueDialog.new(parent, issue)
      dialog.window_position = Gtk::Window::POS_CENTER_ON_PARENT
      dialog.show_all()
      dialog.run() do |response|
        case response
          when Gtk::Dialog::ResponseType::OK
            issue.title = dialog.issue_title.text
            issue.desc = dialog.issue_desc.get_text()
            issue.changed!
            self.update()
        end
      end
      dialog.destroy()
    end
  end

  def update()
    @model.clear()
    $project.unassigned_issues().each do |issue|
      iter = @model.append()
      iter[0] = issue.name
      iter[1] = issue.title
    end
  end
end

class IssueListWindow < Gtk::Window
  def initialize()
    super()
    self.set_title('gDitz')
    self.set_default_size(400, 300)
    swin = Gtk::ScrolledWindow.new()
    swin.set_policy Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC
    ilist = IssueListView.new(self)
    ilist.update()
    self.add(swin.add(ilist))
    self.signal_connect "destroy" do
      changed_issues = $project.issues.select { |i| i.changed? }
      unless changed_issues.empty?
        $storage.save $project
	  end
      Gtk.main_quit()
    end
  end
end

win = IssueListWindow.new()
win.show_all()
Gtk.main()
