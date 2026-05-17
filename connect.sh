ip=${1}
echo "The password is: plugin-workshop-2026"
ssh -o TCPKeepAlive=yes -o ServerAliveInterval=120 $(for i in 8000 8001 7700 2025 1984 1993 1994 1995 1996 1997 1998 1999 2000 2001 2002; do echo -L ${i}:localhost:${i}; done) workshop_dev@${ip}
