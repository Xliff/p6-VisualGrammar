use v6.c;

use GTK::Compat::Types;
use GTK::Raw::Types;

use GTK::Application;
use GTK::Clipboard;
use GTK::Dialog::FileChooser;
use GTK::Menu;
use GTK::MenuBar;
use GTK::Pane;
use GTK::ScrolledWindow;
use GTK::TextView;
use GTK::Box;

class VisualGrammar {
  has GTK::Application    $!app;
  has GTK::Pane           $!hpane;
  has GTK::Pane           $!vpane;
  has GTK::TextView       $!gedit;
  has GTK::TextView       $!tview;
  has GTK::TextView       $!mview;
  has GTK::ScrolledWindow $!gscroll;
  has GTK::ScrolledWindow $!tscroll;
  has GTK::ScrolledWindow $!mscroll;
  has GTK::Clipboard      $!clip;

  has $!paste-text;

  method quit      { $!app.exit }

  method FALLBACK ($name, |c) {
    say "NYO -- { $name } method NYI!";
  }

  method paste {
    $!tview.text = $!clip.wait_for_text;
  }

  method open-file {
    my $fc = GTK::Dialog::FileChooser.new(
      'Select Grammar file', $!app.window, GTK_FILE_CHOOSER_ACTION_OPEN
    );
    $fc.selection-changed.tap: { $fc.filename };
    $fc.response.tap:          { $!gedit.text = $fc.filename.IO.open.slurp;
                                 $!gedit.vadjustment.value = 0;
                                 $!gedit.hadjustment.value = 0;
                                 $fc.hide };
    $fc.run;
  }

  submethod BUILD (:$!app, :$window) {
    # my $menubar = MenuBuilder.new(:menubar, {
    #   File => [
    #     Open  => { clicked => -> { self.open-file  } },
    #     Save  => { clicked => -> { self.save-file  } },
    #     Close => { clicked => -> { self.close-file } },
    #     Quit  => { clicked => -> { self.quit       } },
    #   ],
    #   Edit => [
    #     Cut   => { clicked => -> { self.cut-selected  } },
    #     Copy  => { clicked => -> { self.copy-selected } },
    #     Paste => { clicked => -> { self.paste         } }.
    #   ]
    #   View => [
    #     'Clear Messages' => { clicked => -> { self.clear-msgs } },
    #   ],
    #   Refresh => { clicked => -> { self.refresh-grammar } }
    # }

    my $menubar = GTK::MenuBar.new(
      GTK::MenuItem.new('File',
        :submenu(
          GTK::Menu.new(
            GTK::MenuItem.new('Open',  :clicked(-> { self.open-file  })),
            GTK::MenuItem.new('Save',  :clicked(-> { self.save-file  })),
            GTK::MenuItem.new('Close', :clicked(-> { self.close-file })),
            GTK::MenuItem.new('Quit',  :clicked(-> { self.quit       }))
          )
        ),
      ),
      GTK::MenuItem.new('Edit',
         :submenu(
           GTK::Menu.new(
             GTK::MenuItem.new('Cut',   :clicked(-> { self.cut-selected  })),
             GTK::MenuItem.new('Copy',  :clicked(-> { self.copy-selected })),
             GTK::MenuItem.new('Paste', :clicked(-> { self.paste         }))
           )
         )
      ),
      GTK::MenuItem.new('View',
        :submenu(
          GTK::Menu.new(
            GTK::MenuItem.new('Clear Messages', :clicked(-> { self.clear-msgs }))
          )
        )
      ),
      GTK::MenuItem.new('Refresh', :clicked(-> { self.refresh-grammar }))
    );

    my $vbox = GTK::Box.new-vbox;
    ($!hpane, $!vpane) = (GTK::Pane.new-hpane, GTK::Pane.new-vpane);
    ($!gedit, $!tview, $!mview) = (GTK::TextView.new xx 3);
    ($!gedit.editable, $!tview.editable, $!mview.editable) = (True, False, False);
    ($!hpane.wide-handle, $!vpane.wide-handle) = (True, True);
    ($!gscroll, $!tscroll, $!mscroll) = (GTK::ScrolledWindow.new xx 3);
    .set_policy(GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC)
      for $!gscroll, $!tscroll, $!mscroll;
    $!gscroll.set_size_request(400, 300);
    $!tscroll.set_size_request(400, 400);
    $!mscroll.set_size_request(400, 100);
    $vbox.set_size_request(800, 400);
    ($!hpane.position, $!vpane.position) = (400, 300);
    $!gscroll.add($!gedit);
    $!mscroll.add($!mview);
    $!tscroll.add($!tview);
    $!vpane.add1($!gscroll);
    $!vpane.add2($!mscroll);
    $!hpane.add1($!vpane);
    $!hpane.add2($!tscroll);

    $!clip = GTK::Clipboard.new( GDK_SELECTION_CLIPBOARD );
    $!tview.paste-clipboard.tap({ self.paste });

    $vbox.add($menubar);
    $vbox.add($!hpane);
    $window.add($vbox);
  }
}
