// The contents of this file are used with permission, subject to
// the Mozilla Public License Version 1.1 (the "License"); you may
// not use this file except in compliance with the License. You may
// obtain a copy of the License at
// http://www.mozilla.org/MPL/MPL-1.1.html
//
// Software distributed under the License is distributed on an
// "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
// implied. See the License for the specific language governing
// rights and limitations under the License.
unit DnConst;

interface

const
  ErrWin32Error =                   0;
  ErrInvalidParameter =             1;
  ErrObjectNotActive =              2;
  ErrCannotGetCGIParamValue =       3;
  ErrCannotGetCGINullValue =        4;
  ErrCannotParseUrlencodedString =  5;
  ErrCannotParseCookie =            6;
  ErrObjectIsActive =               7;
  ErrCannotParseHttpHeader =        8;
  ErrCannotParseHttpTime =          9;
  ErrCannotParseHttp =              10;
  ErrInvalidConfig =                11;
  ErrCannotSetTimeOutTwice =        12;
  ErrChannelClosing =               13;
  ErrCannotRemoveOpenedChannel =    14;
  ErrZeroTransferDetected =         15;
  ErrRequiresNT4 =                  16;
  
  ExceptionMessages: array [0..16] of string =
  (
  'Win32 system error.',
  'Invalid parameter passed to function.',
  'Object is not active.',
  'Cannot get param array value.',
  'Cannot get NULL as value.',
  'Cannot parse urlencoded string.',
  'Cannot parse the cookie string.',
  'Object is active.',
  'Cannot parse the HTTP header.',
  'Cannot parse the time string.',
  'Cannot parse the HTTP data.',
  'Invalid configuration of object.',
  'Cannot set timeout twice to channel.',
  'Channel is closing. No operations permitted.',
  'Cannot remove from reactor opened channel.',
  'Internal error. Zero transfer was detected.',
  'This module requires at least NT4 system with SP6.'
  );

  SCannotAccept = 'Cannot accept incoming connection on port %d for socket %d. Error code is %d';
  SCannotRemoveThread = 'Cannot remove thread.';
  SCannotCreateThread = 'Cannot create thread.';
  
  
implementation

end.




