{
  notification-daemon ? callPackage ./notification-daemon { },
  notify ? callPackage ./notify { },
}:
{
  inherit notification-daemon notify;
}
