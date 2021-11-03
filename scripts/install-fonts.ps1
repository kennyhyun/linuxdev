$FONTS = 0x14
$CopyOptions = 4 + 16;
$objShell = New-Object -ComObject Shell.Application
$objFolder = $objShell.Namespace($FONTS)

foreach($font_file_name in $args) {
  $font = dir "$PSScriptRoot\..\data\fonts\$font_file_name"
  write-host "Installing $font"
  $CopyFlag = [String]::Format("{0:x}", $CopyOptions);
  $objFolder.CopyHere($font.fullname,$CopyFlag)
}
