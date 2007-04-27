#!/usr/bin/ksh


dsh -t 120 /usr/bin/networker.cluster -r
dsh -t 120 /usr/bin/networker.cluster -r
dsh -t 120 /usr/bin/networker.cluster -r

dsh -t 120 installp -u LGTOnw.clnt.rte LGTOnw.licm.rte LGTOnw.man.rte LGTOnw.node.rte LGTOnw.serv.rte
